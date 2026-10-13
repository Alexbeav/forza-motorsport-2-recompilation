[CmdletBinding()]
param()

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('fm2-launcher-tests-' + [Guid]::NewGuid().ToString('N'))
foreach ($directory in @('tools', 'release', 'fm2', 'build with spaces', 'game with spaces')) {
    [IO.Directory]::CreateDirectory((Join-Path $fixture $directory)) | Out-Null
}
foreach ($file in @('tools/Release.Common.ps1', 'tools/Launcher.Common.ps1', 'release/release-policy.json', 'fm2/fm2_runtime.toml')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $fixture $file)
}
$xex = Join-Path $fixture 'game with spaces/default.xex'
[IO.File]::WriteAllText($xex, 'Synthetic fixture. Never executed.')
$policy = Get-Content -LiteralPath (Join-Path $fixture 'release/release-policy.json') -Raw | ConvertFrom-Json
$policy.required_game_inputs[0].size = (Get-Item -LiteralPath $xex).Length
$policy.required_game_inputs[0].sha256 = (Get-FileHash -LiteralPath $xex).Hash
[IO.File]::WriteAllText((Join-Path $fixture 'release/release-policy.json'), ($policy | ConvertTo-Json -Depth 8))
. (Join-Path $fixture 'tools/Launcher.Common.ps1')
$passed = 0
function Assert([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
    $script:passed++
}
function Reject([scriptblock]$Action, [string]$Pattern) {
    $message = ''
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($message -like $Pattern) "Expected '$Pattern'; got '$message'"
}
$settings = Get-Fm2LauncherDefaults
$settings.ExecutablePath = Join-Path $fixture 'build with spaces/fm2.exe'
$settings.GameDataRoot = Split-Path -Parent $xex
$settings.UserDataRoot = Join-Path $fixture 'existing profile with spaces'
$settings.ContentRoot = $settings.GameDataRoot
[IO.File]::WriteAllText($settings.ExecutablePath, 'Non-executable fixture. Never launched.')
$plugin = Join-Path $fixture 'build with spaces/rexgpu-xenos.dll'
[IO.File]::WriteAllText($plugin, 'Non-executable plugin fixture.')
$runtime = Join-Path $fixture 'build with spaces/rexruntime.dll'
[IO.File]::WriteAllText($runtime, 'Non-executable runtime fixture.')
$receipt = @{ features = @('gpu_max_fps', 'window_size_in_pixels'); artifacts = @(@{ path = 'rexgpu-xenos.dll'; sha256 = (Get-FileHash -LiteralPath $plugin).Hash }, @{ path = 'rexruntime.dll'; sha256 = (Get-FileHash -LiteralPath $runtime).Hash }) }
$receiptPath = Join-Path $fixture 'build with spaces/build-provenance.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 4))
$config = Join-Path $fixture 'build with spaces/fm2.toml'
$sentinel = '# keep this comment' + "`nreadback_resolve_mode = `"fast`"`n  vsync = false # old`nvsync = true`nwindow_width = 1280`nfm2_content_trace = true`n"
[IO.File]::WriteAllText($config, $sentinel)
$settingsPath = Join-Path $fixture 'preferences/settings.json'
Save-Fm2LauncherSettings $settingsPath $settings
$loaded = Read-Fm2LauncherSettings $settingsPath
Assert (($loaded | ConvertTo-Json -Compress) -eq ($settings | ConvertTo-Json -Compress)) 'Preferences did not round-trip.'
foreach ($cap in @(0, 30, 60, 120, 1000)) {
    foreach ($scale in @(1, 2, 3)) {
        $loaded.MaxFps = $cap; $loaded.Scale = $scale
        $loaded.VSync = $false; $loaded.Fullscreen = $true; $loaded.Width = 1920; $loaded.Height = 1080
        $plan = New-Fm2LauncherPlan $loaded
        Assert ($plan.SupportsFpsCap -and $plan.RuntimeConfiguration -match "(?m)^gpu_max_fps = $cap$") 'FPS mapping failed.'
        Assert ($plan.RuntimeConfiguration -match "(?m)^draw_resolution_scale_x = $scale$" -and $plan.RuntimeConfiguration -match "(?m)^draw_resolution_scale_y = $scale$") 'Scale mapping failed.'
        Assert ($plan.RuntimeConfiguration -match '(?m)^fullscreen = true$' -and $plan.RuntimeConfiguration -match '(?m)^window_width = 1920$' -and $plan.RuntimeConfiguration -match '(?m)^window_height = 1080$') 'Window mapping failed.'
    }
}
Assert ($plan.RuntimeConfiguration -match '(?m)^vsync = false$' -and [regex]::Matches($plan.RuntimeConfiguration, '(?m)^\s*vsync\s*=').Count -eq 1) 'Duplicate managed keys remained.'
Assert ($plan.RuntimeConfiguration.Contains('readback_resolve_mode = "fast"') -and $plan.RuntimeConfiguration.Contains('# keep this comment') -and $plan.RuntimeConfiguration.Contains('fm2_content_trace = true')) 'Unrelated settings were lost.'
Assert ($plan.SupportsPixelResolution -and $plan.RuntimeConfiguration -match '(?m)^window_size_in_pixels = true$') 'Pixel resolution mode was not enabled.'
Assert ($plan.Arguments -contains "--game_data_root=$($settings.GameDataRoot)" -and $plan.Arguments -contains "--user_data_root=$($settings.UserDataRoot)" -and $plan.Arguments -contains "--fm2_content_root=$($settings.ContentRoot)") 'Paths with spaces were split.'
Assert (-not (Test-Path -LiteralPath $loaded.UserDataRoot) -and [IO.File]::ReadAllText($config) -ceq $sentinel) 'Validation wrote game configuration or profile data.'
[IO.File]::AppendAllText($plugin, 'changed')
Reject { New-Fm2LauncherPlan $loaded } 'This build has no verified FPS limiter*'
$loaded.MaxFps = 0
[IO.File]::AppendAllText($config, 'gpu_max_fps = 30')
$old = New-Fm2LauncherPlan $loaded
Assert (-not $old.SupportsFpsCap -and $old.RuntimeConfiguration -notmatch 'gpu_max_fps') 'An old runtime claimed FPS support.'
[IO.File]::WriteAllText($config, $sentinel)
[IO.File]::AppendAllText($runtime, 'changed')
$loaded.Fullscreen = $false
Reject { New-Fm2LauncherPlan $loaded } 'This build scales window dimensions*'
$loaded.Fullscreen = $true
$loaded.Width = 1
Reject { New-Fm2LauncherPlan $loaded } 'Window resolution*'
$loaded.Width = 1280; $loaded.MaxFps = 1001
Reject { New-Fm2LauncherPlan $loaded } 'FPS cap*'
$loaded.MaxFps = 0; $loaded.Scale = 4
Reject { New-Fm2LauncherPlan $loaded } 'Render scale*'
$loaded.Scale = 1; $loaded.VSync = 'false'
Reject { New-Fm2LauncherPlan $loaded } 'VSync must*'
$loaded.VSync = $false; $loaded.UserDataRoot = $xex
Reject { New-Fm2LauncherPlan $loaded } 'The profile path is a file*'
$loaded.UserDataRoot = Join-Path $settings.GameDataRoot 'user'
Reject { New-Fm2LauncherPlan $loaded } 'Select a separate profile folder*'
$loaded.UserDataRoot = $settings.UserDataRoot; $loaded.GameDataRoot = Join-Path $fixture 'missing'
Reject { New-Fm2LauncherPlan $loaded } 'Game data folder not found*'
Reject { Merge-Fm2RuntimeConfiguration "[GPU]`nvsync=true" @{vsync=$true} } 'The launcher needs a flat*'

# Exercise the real process-start path with a PowerShell child, never FM2.
$capture = Join-Path $fixture 'capture arguments.ps1'
[IO.File]::WriteAllText($capture, '@{ Arguments=@([Environment]::GetCommandLineArgs() | Select-Object -Skip 4); SkipIntro=$env:FM2_SKIP_INTRO } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot "captured.json")')
$launch = [pscustomobject]@{
    Executable = (Get-Command pwsh).Source
    WorkingDirectory = $fixture
    Arguments = @('-NoProfile', '-File', $capture) + $plan.Arguments
    UserDataRoot = Join-Path $fixture 'child profile'
    ConfigPath = $config
    RuntimeConfiguration = $plan.RuntimeConfiguration
}
if (-not (Get-Process -Name fm2 -ErrorAction SilentlyContinue)) {
    $child = Start-Fm2LauncherPlan $launch
    $child.WaitForExit()
    Assert ($child.ExitCode -eq 0) 'The harmless child failed.'
    $captured = Get-Content -LiteralPath (Join-Path $fixture 'captured.json') -Raw | ConvertFrom-Json
    Assert ($captured.Arguments.Count -eq $plan.Arguments.Count -and $captured.Arguments[1] -ceq $plan.Arguments[1] -and $captured.SkipIntro -eq '1') 'Process startup split paths or lost the intro setting.'
    Assert ([IO.File]::ReadAllText($config + '.launcher-backup') -ceq $sentinel) 'Configuration backup changed.'
    Assert ([IO.File]::ReadAllText($config) -ceq $plan.RuntimeConfiguration) 'Start did not write the selected settings.'
}
Write-Host "Launcher tests passed: $passed assertions. No game started. Evidence: $fixture"
