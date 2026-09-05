[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GameDataRoot,
    [string]$ContentRoot,
    [switch]$TraceContent
)

. (Join-Path $PSScriptRoot "Release.Common.ps1")

$root = Get-Fm2RepositoryRoot
$resolvedGameRoot = Assert-Fm2GameInputs -GameDataRoot $GameDataRoot
$buildRoot = Join-Path $root ".local/work/fm2/out/build/win-amd64-release"
$executable = Join-Path $buildRoot "fm2.exe"
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Local build not found. Run tools/Build-Local.ps1 first."
}

Copy-Item -LiteralPath (Join-Path $root ".local/work/fm2/fm2_runtime.toml") -Destination (Join-Path $buildRoot "fm2.toml") -Force
$localUserRoot = Join-Path $root ".local/user"
[IO.Directory]::CreateDirectory($localUserRoot) | Out-Null
$arguments = @(
    "--game_data_root=$resolvedGameRoot",
    "--user_data_root=$localUserRoot"
)
if ($ContentRoot) {
    $resolvedContentRoot = [IO.Path]::GetFullPath($ContentRoot)
    if (-not (Test-Path -LiteralPath $resolvedContentRoot -PathType Container)) {
        throw "FM2 content folder not found: $resolvedContentRoot"
    }
    $arguments += "--fm2_content_root=$resolvedContentRoot"
}
if ($TraceContent) { $arguments += "--fm2_content_trace=true" }

$previousSkipIntro = $env:FM2_SKIP_INTRO
$env:FM2_SKIP_INTRO = "1"
try {
    Invoke-CheckedNative -FilePath $executable -ArgumentList $arguments -WorkingDirectory $buildRoot
}
finally {
    $env:FM2_SKIP_INTRO = $previousSkipIntro
}
