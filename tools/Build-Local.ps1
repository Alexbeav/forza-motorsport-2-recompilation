[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GameDataRoot,
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$SdkSourceRoot,
    [switch]$ValidateOnly
)

. (Join-Path $PSScriptRoot "Release.Common.ps1")

if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne "X64") {
    throw "The validated local builder currently supports Windows AMD64 only."
}

$root = Get-Fm2RepositoryRoot
$policy = Get-Fm2ReleasePolicy
& (Join-Path $PSScriptRoot "Test-RepositoryBoundary.ps1") -AllowLocalBuildOutputs
$sourceIdentity = Get-Fm2SourceIdentity
$resolvedGameRoot = Assert-Fm2GameInputs -GameDataRoot $GameDataRoot
$git = Resolve-Fm2Tool -Name "git"
$cmake = Resolve-Fm2Tool -Name "cmake"
$clang = Resolve-Fm2Tool -Name "clang"
$clangxx = Resolve-Fm2Tool -Name "clang++"
$clangcl = Resolve-Fm2Tool -Name "clang-cl"
$ninja = Resolve-Fm2Tool -Name "ninja"
$compilerTarget = (& $clangxx -dumpmachine).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerTarget -notmatch "windows-msvc$") {
    throw "Clang must target the MSVC ABI; detected target: $compilerTarget"
}

if ($ValidateOnly) {
    Write-Host "Source identity, input, and toolchain validation passed. No SDK source was downloaded and no code was generated."
    return
}

$localRoot = Join-Path $root ".local"
$sdkSource = if ($SdkSourceRoot) { [IO.Path]::GetFullPath($SdkSourceRoot) } else { Join-Path $localRoot "rexglue-sdk" }
[IO.Directory]::CreateDirectory($localRoot) | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $sdkSource ".git"))) {
    if ($SdkSourceRoot) {
        throw "The supplied SDK source is not a Git checkout: $sdkSource"
    }
    if (Test-Path -LiteralPath $sdkSource) {
        throw "SDK source path exists but is not a Git checkout: $sdkSource"
    }
    Invoke-CheckedNative -FilePath $git -ArgumentList @("clone", "--no-checkout", $policy.sdk.repository, $sdkSource) -WorkingDirectory $root
    Invoke-CheckedNative -FilePath $git -ArgumentList @("checkout", "--detach", $policy.sdk.commit) -WorkingDirectory $sdkSource
    Invoke-CheckedNative -FilePath $git -ArgumentList @("submodule", "update", "--init", "--recursive") -WorkingDirectory $sdkSource
}

$sdkHead = (& $git -C $sdkSource rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sdkHead -ne $policy.sdk.commit) {
    throw "SDK checkout is not at the required commit $($policy.sdk.commit): $sdkHead"
}
$sdkDirty = @(& $git -C $sdkSource status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $sdkDirty.Count -ne 0) {
    throw "SDK checkout has tracked modifications. Refusing a non-pinned toolchain build."
}
$submoduleStatus = @(& $git -C $sdkSource submodule status --recursive)
if ($LASTEXITCODE -ne 0 -or @($submoduleStatus | Where-Object { $_ -match "^[-+]" }).Count -ne 0) {
    throw "SDK submodules are missing or do not match the pinned SDK commit."
}

$sdkBuild = Join-Path $localRoot "sdk-build"
$sdkInstall = Join-Path $localRoot "sdk-install"
Invoke-CheckedNative -FilePath $cmake -ArgumentList @(
    "-S", $sdkSource,
    "-B", $sdkBuild,
    "-G", "Ninja Multi-Config",
    "-DCMAKE_C_COMPILER=$clang",
    "-DCMAKE_CXX_COMPILER=$clangxx",
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DCMAKE_C_FLAGS=-march=x86-64-v3",
    "-DCMAKE_CXX_FLAGS=-march=x86-64-v3",
    "-DCMAKE_CXX_STANDARD=23",
    "-DCMAKE_CONFIGURATION_TYPES=Release",
    "-DCMAKE_INSTALL_PREFIX=$sdkInstall"
) -WorkingDirectory $sdkSource
$sdkPatch = Join-Path $root "release/sdk-fps-cap.patch"
Invoke-CheckedNative -FilePath $git -ArgumentList @("apply", "--check", $sdkPatch) -WorkingDirectory $sdkSource
Invoke-CheckedNative -FilePath $git -ArgumentList @("apply", $sdkPatch) -WorkingDirectory $sdkSource
try {
    Invoke-CheckedNative -FilePath $cmake -ArgumentList @(
        "--build", $sdkBuild, "--config", "Release", "--target", "install", "--parallel", $Jobs
    ) -WorkingDirectory $sdkSource
}
finally {
    # The SDK checkout stays pinned and clean; only its local build has the patch.
    Invoke-CheckedNative -FilePath $git -ArgumentList @("apply", "--reverse", $sdkPatch) -WorkingDirectory $sdkSource
}

$rexglue = Join-Path $sdkInstall "bin/rexglue.exe"
if (-not (Test-Path -LiteralPath $rexglue -PathType Leaf)) {
    throw "Pinned SDK build did not install rexglue.exe at $rexglue"
}

$projectWorkRoot = Join-Path $localRoot "work"
if (Test-Path -LiteralPath $projectWorkRoot) {
    $resolvedWorkRoot = [IO.Path]::GetFullPath($projectWorkRoot)
    if ((Split-Path -Parent $resolvedWorkRoot) -ne [IO.Path]::GetFullPath($localRoot)) {
        throw "Refusing to replace a build workspace outside .local: $resolvedWorkRoot"
    }
    if ((Get-Item -LiteralPath $resolvedWorkRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to move a linked build workspace: $resolvedWorkRoot"
    }
    $previousRoot = Join-Path $localRoot "previous-builds"
    [IO.Directory]::CreateDirectory($previousRoot) | Out-Null
    $previousWork = [IO.Path]::GetFullPath((Join-Path $previousRoot ("work-" + [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + [Guid]::NewGuid().ToString("N"))))
    if (-not $previousWork.StartsWith([IO.Path]::GetFullPath($localRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to move a build workspace outside .local."
    }
    Move-Item -LiteralPath $resolvedWorkRoot -Destination $previousWork
    Write-Host "Previous build preserved: $previousWork"
}
[IO.Directory]::CreateDirectory($projectWorkRoot) | Out-Null
$sourceAllowlist = @(Get-Content -LiteralPath (Join-Path $root $policy.source_allowlist) | ForEach-Object { $_.Trim().Replace("\", "/") } | Where-Object { $_ -and -not $_.StartsWith("#") })
foreach ($relativePath in $sourceAllowlist) {
    $source = Join-Path $root $relativePath
    $destination = Join-Path $projectWorkRoot $relativePath
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

# Hash the copied inputs, not files that can change while the SDK builds.
$copiedRecords = @(Get-Fm2FileRecords -Paths @($sourceAllowlist | ForEach-Object { Join-Path $projectWorkRoot $_ }) -BasePath $projectWorkRoot)
if (($copiedRecords | ConvertTo-Json -Depth 4 -Compress) -cne ($sourceIdentity.files | ConvertTo-Json -Depth 4 -Compress)) {
    throw "Source files changed during the build. Start the build again from a stable source tree."
}

$fm2Root = Join-Path $projectWorkRoot "fm2"
$manifestTemplate = Join-Path $fm2Root "fm2_manifest.toml"
$localManifest = Join-Path $fm2Root "fm2_manifest.local.toml"
$tomlGameRoot = $resolvedGameRoot.Replace("\", "/").Replace('"', '\"')
$manifest = (Get-Content -LiteralPath $manifestTemplate -Raw).Replace("../extracted", $tomlGameRoot)
Set-Content -LiteralPath $localManifest -Value $manifest -Encoding utf8NoBOM

Invoke-CheckedNative -FilePath $rexglue -ArgumentList @("codegen", $localManifest) -WorkingDirectory $fm2Root
Invoke-CheckedNative -FilePath $cmake -ArgumentList @(
    "--preset", "win-amd64-release", "--fresh",
    "-DREXSDK_PACKAGE_DIR=$sdkInstall",
    "-DCMAKE_C_COMPILER=$clangcl",
    "-DCMAKE_CXX_COMPILER=$clangcl"
) -WorkingDirectory $fm2Root
Invoke-CheckedNative -FilePath $cmake -ArgumentList @(
    "--build", "--preset", "win-amd64-release", "--parallel", $Jobs
) -WorkingDirectory $fm2Root

$buildRoot = Join-Path $fm2Root "out/build/win-amd64-release"
Copy-Item -LiteralPath (Join-Path $fm2Root "fm2_runtime.toml") -Destination (Join-Path $buildRoot "fm2.toml") -Force
$artifacts = @(
    "fm2.exe",
    "rexgpu-xenos.dll",
    "rexruntime.dll",
    "TracyClient.dll",
    "fm2.toml"
) | ForEach-Object { Join-Path $buildRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

if (-not (Test-Path -LiteralPath (Join-Path $buildRoot "fm2.exe") -PathType Leaf)) {
    throw "FM2 build completed without the expected executable."
}

$receipt = [ordered]@{
    schema_version = 1
    generated_locally = $true
    created_utc = [DateTime]::UtcNow.ToString("o")
    project_commit = $sourceIdentity.project_commit
    project_worktree_dirty = $sourceIdentity.project_worktree_dirty
    source_kind = $sourceIdentity.kind
    source_provenance_sha256 = $sourceIdentity.source_provenance_sha256
    source_files = $copiedRecords
    sdk_repository = $policy.sdk.repository
    sdk_commit = $sdkHead
    sdk_patches = @([ordered]@{ path = "release/sdk-fps-cap.patch"; sha256 = (Get-FileHash -LiteralPath $sdkPatch).Hash })
    features = @("gpu_max_fps")
    game_inputs = @($policy.required_game_inputs)
    artifacts = Get-Fm2FileRecords -Paths $artifacts -BasePath $buildRoot
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $buildRoot "build-provenance.json") -Encoding utf8NoBOM

Write-Host "Local build complete: $buildRoot"
Write-Host "Run it with: pwsh -File .\tools\Run-Local.ps1 -GameDataRoot `"$resolvedGameRoot`""
