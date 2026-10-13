[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GameDataRoot,
    [string]$ContentRoot,
    [string]$UserDataRoot,
    [switch]$TraceContent,
    [switch]$ValidateOnly
)

. (Join-Path $PSScriptRoot "Release.Common.ps1")

$root = Get-Fm2RepositoryRoot
$resolvedGameRoot = Assert-Fm2GameInputs -GameDataRoot $GameDataRoot
$buildRoot = Join-Path $root ".local/work/fm2/out/build/win-amd64-release"
$executable = Join-Path $buildRoot "fm2.exe"
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Local build not found. Run tools/Build-Local.ps1 first."
}

$template = [IO.File]::ReadAllText((Join-Path $root ".local/work/fm2/fm2_runtime.toml"))
# This SDK loads the flat runtime configuration after command-line values.
# Write the requested trace value there so the template's false value cannot win.
$runtimeConfiguration = [regex]::Replace($template, '(?m)^fm2_content_trace\s*=.*\r?\n?', '').TrimEnd()
$runtimeConfiguration += "`nfm2_content_trace = $($TraceContent.IsPresent.ToString().ToLowerInvariant())`n"
$localUserRoot = if ($UserDataRoot) { [IO.Path]::GetFullPath($UserDataRoot) } else { Join-Path $root ".local/user" }
if ((Test-Path -LiteralPath $localUserRoot) -and -not (Test-Path -LiteralPath $localUserRoot -PathType Container)) {
    throw "User data path is not a folder: $localUserRoot"
}
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

if ($ValidateOnly) {
    [pscustomobject]@{ Executable = $executable; Arguments = $arguments; UserDataRoot = $localUserRoot; RuntimeConfiguration = $runtimeConfiguration; Launched = $false }
    return
}
if (Get-Process -Name fm2 -ErrorAction SilentlyContinue) { throw "Close FM2 before starting another local run." }
[IO.Directory]::CreateDirectory($localUserRoot) | Out-Null
[IO.File]::WriteAllText((Join-Path $buildRoot "fm2.toml"), $runtimeConfiguration)

$previousSkipIntro = $env:FM2_SKIP_INTRO
$env:FM2_SKIP_INTRO = "1"
try {
    Invoke-CheckedNative -FilePath $executable -ArgumentList $arguments -WorkingDirectory $buildRoot
}
finally {
    $env:FM2_SKIP_INTRO = $previousSkipIntro
}
