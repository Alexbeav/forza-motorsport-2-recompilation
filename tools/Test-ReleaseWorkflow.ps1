[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "Release.Common.ps1")
$root = Get-Fm2RepositoryRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("fm2-release-tests-" + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$passed = 0

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}

function Assert-Fails([scriptblock]$Action, [string]$MessagePattern) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-Condition ($null -ne $failure -and $failure -like $MessagePattern) "Expected failure '$MessagePattern', got '$failure'."
}

# Keep fixtures and test receipts for inspection. No game or SDK is required.
$version = "0.1.0-test"
foreach ($name in @("a", "b")) {
    & (Join-Path $root "tools/New-SourceRelease.ps1") -Version $version -OutputDirectory (Join-Path $testRoot $name) -AllowDirty
}
$archiveName = "fm2-recomp-source-$version"
$archiveA = Join-Path $testRoot "a/$archiveName.zip"
$archiveB = Join-Path $testRoot "b/$archiveName.zip"
Assert-Condition ((Get-FileHash -LiteralPath $archiveA).Hash -eq (Get-FileHash -LiteralPath $archiveB).Hash) "Source archives are not deterministic."

$extractRoot = Join-Path $testRoot "unpacked"
[IO.Compression.ZipFile]::ExtractToDirectory($archiveA, $extractRoot)
$packageRoot = Join-Path $extractRoot $archiveName
$identity = Get-Fm2SourceIdentity -Root $packageRoot
Assert-Condition ($identity.kind -eq "source-archive") "The archive did not use packaged provenance."
Assert-Condition ($identity.project_commit -eq (Get-Fm2SourceIdentity).project_commit) "The archive commit differs from the source commit."
Assert-Condition ($identity.source_provenance_sha256 -match '^[0-9A-F]{64}$') "The archive provenance hash is missing."
& (Join-Path $packageRoot "tools/Test-RepositoryBoundary.ps1")

# A parent Git checkout must never supply an archive's commit or clean status.
Invoke-CheckedNative -FilePath (Resolve-Fm2Tool git) -ArgumentList @("init", "--quiet", $extractRoot)
$nestedIdentity = Get-Fm2SourceIdentity -Root $packageRoot
Assert-Condition ($nestedIdentity.kind -eq "source-archive" -and $nestedIdentity.project_commit -eq $identity.project_commit) "A parent Git repository changed archive identity."

$readme = Join-Path $packageRoot "README.md"
$readmeBytes = [IO.File]::ReadAllBytes($readme)
[IO.File]::AppendAllText($readme, "`nChanged fixture.`n")
Assert-Fails { Get-Fm2SourceIdentity -Root $packageRoot } "Source provenance mismatch: README.md*"
[IO.File]::WriteAllBytes($readme, $readmeBytes)

$provenancePath = Join-Path $packageRoot "SOURCE-PROVENANCE.json"
$provenanceBytes = [IO.File]::ReadAllBytes($provenancePath)
$provenance = [Text.Encoding]::UTF8.GetString($provenanceBytes) | ConvertFrom-Json
$provenance.project_worktree_dirty = $true
[IO.File]::WriteAllText($provenancePath, ($provenance | ConvertTo-Json -Depth 8))
Assert-Condition ((Get-Fm2SourceIdentity -Root $packageRoot).project_worktree_dirty) "Dirty archive provenance became clean."
$provenance.sdk_commit = "0" * 40
[IO.File]::WriteAllText($provenancePath, ($provenance | ConvertTo-Json -Depth 8))
Assert-Fails { Get-Fm2SourceIdentity -Root $packageRoot } "Source provenance does not match the release policy.*"
[IO.File]::WriteAllBytes($provenancePath, $provenanceBytes)

$provenance = [Text.Encoding]::UTF8.GetString($provenanceBytes) | ConvertFrom-Json
$provenance.payload[0].path = "../outside.txt"
[IO.File]::WriteAllText($provenancePath, ($provenance | ConvertTo-Json -Depth 8))
Assert-Fails { Get-Fm2SourceIdentity -Root $packageRoot } "Source provenance mismatch:*"
[IO.File]::WriteAllBytes($provenancePath, $provenanceBytes)
[IO.File]::Move($provenancePath, "$provenancePath.fixture")
Assert-Fails { Get-Fm2SourceIdentity -Root $packageRoot } "Source identity is missing.*"
[IO.File]::Move("$provenancePath.fixture", $provenancePath)

# A second user build permits .local, but strict package inspection rejects it.
$localOutput = Join-Path $packageRoot ".local/output"
[IO.Directory]::CreateDirectory($localOutput) | Out-Null
[IO.File]::WriteAllText((Join-Path $localOutput "artifact.exe"), "MZfixture")
Assert-Fails { & (Join-Path $packageRoot "tools/Test-RepositoryBoundary.ps1") } "Repository file is absent from the source allowlist: .local/*"
& (Join-Path $packageRoot "tools/Test-RepositoryBoundary.ps1") -AllowLocalBuildOutputs
$null = Get-Fm2SourceIdentity -Root $packageRoot

# The same identity object supplies the real builder's receipt fields.
$receiptPath = Join-Path $testRoot "archive-receipt-fixture.json"
[IO.File]::WriteAllText($receiptPath, ($identity | ConvertTo-Json -Depth 8))
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
Assert-Condition ($receipt.project_commit -eq $identity.project_commit -and $receipt.files.Count -eq $identity.files.Count) "Archive identity did not survive receipt serialization."

if ($IsWindows) {
    Assert-Fails { Invoke-CheckedNative -FilePath $env:ComSpec -ArgumentList @("/d", "/c", "exit 7") } "Command failed with exit code 7:*"
    Invoke-CheckedNative -FilePath $env:ComSpec -ArgumentList @("/d", "/c", "exit 0")
}

# Validate the launch plan with synthetic inputs. The placeholder is never executed.
$fixtureGame = Join-Path $testRoot "synthetic game with spaces"
[IO.Directory]::CreateDirectory($fixtureGame) | Out-Null
$fixtureXex = Join-Path $fixtureGame "default.xex"
[IO.File]::WriteAllText($fixtureXex, "Synthetic launch-plan fixture, not an Xbox executable.")
$fixturePolicyPath = Join-Path $packageRoot "release/release-policy.json"
$fixturePolicy = Get-Content -LiteralPath $fixturePolicyPath -Raw | ConvertFrom-Json
$fixturePolicy.required_game_inputs[0].size = (Get-Item -LiteralPath $fixtureXex).Length
$fixturePolicy.required_game_inputs[0].sha256 = (Get-FileHash -LiteralPath $fixtureXex).Hash
[IO.File]::WriteAllText($fixturePolicyPath, ($fixturePolicy | ConvertTo-Json -Depth 8))
$fixtureWork = Join-Path $packageRoot ".local/work/fm2"
$fixtureBuild = Join-Path $fixtureWork "out/build/win-amd64-release"
[IO.Directory]::CreateDirectory($fixtureBuild) | Out-Null
[IO.File]::WriteAllText((Join-Path $fixtureBuild "fm2.exe"), "Non-executable launch-plan fixture.")
Copy-Item -LiteralPath (Join-Path $packageRoot "fm2/fm2_runtime.toml") -Destination (Join-Path $fixtureWork "fm2_runtime.toml")
$sentinelPath = Join-Path $fixtureBuild "fm2.toml"
[IO.File]::WriteAllText($sentinelPath, ([IO.File]::ReadAllText((Join-Path $fixtureWork 'fm2_runtime.toml')) + "`nvsync = false`n# Validation must not overwrite this file.`n"))
$sentinelHash = (Get-FileHash -LiteralPath $sentinelPath).Hash
$fixtureUser = Join-Path $testRoot "short user with spaces"
$runner = Join-Path $packageRoot "tools/Run-Local.ps1"
$plan = & $runner -GameDataRoot $fixtureGame -UserDataRoot $fixtureUser -ContentRoot $fixtureGame -TraceContent -ValidateOnly
Assert-Condition (-not $plan.Launched -and $plan.UserDataRoot -eq $fixtureUser) "The custom user-data root was not retained."
Assert-Condition ($plan.Arguments -contains "--user_data_root=$fixtureUser" -and $plan.Arguments -contains "--game_data_root=$fixtureGame") "Paths with spaces were split in the launch plan."
Assert-Condition ($plan.RuntimeConfiguration -match '(?m)^fm2_content_trace = true$' -and $plan.RuntimeConfiguration -notmatch 'fm2_content_trace\s*=\s*false') "The runtime configuration disabled the requested trace."
Assert-Condition (@([regex]::Matches($plan.RuntimeConfiguration, '(?m)^fm2_content_trace\s*=')).Count -eq 1) "The runtime configuration contains duplicate trace assignments."
Assert-Condition ($plan.RuntimeConfiguration -match '(?m)^resolution_scale = 1\r?$') "The default runtime configuration enables the failed scaling experiment."
Assert-Condition ($plan.RuntimeConfiguration -match '(?m)^vsync = false$') "The run script discarded a saved graphics setting."
Assert-Condition ((Get-FileHash -LiteralPath $sentinelPath).Hash -eq $sentinelHash -and -not (Test-Path -LiteralPath $fixtureUser)) "ValidateOnly changed configuration or created user data."
$defaultPlan = & $runner -GameDataRoot $fixtureGame -ValidateOnly
Assert-Condition ($defaultPlan.UserDataRoot -eq (Join-Path $packageRoot '.local/user') -and $defaultPlan.RuntimeConfiguration -match '(?m)^fm2_content_trace = false$') "Default user data or disabled tracing changed."
Assert-Fails { & $runner -GameDataRoot $fixtureGame -UserDataRoot $fixtureXex -ValidateOnly } "User data path is not a folder:*"
Write-Host "Release workflow tests passed: $passed assertions. Evidence: $testRoot"
