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
Write-Host "Release workflow tests passed: $passed assertions. Evidence: $testRoot"
