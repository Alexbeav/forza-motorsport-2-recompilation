. (Join-Path $PSScriptRoot 'Release.Common.ps1')

function Get-Fm2LauncherDefaults {
    $root = Get-Fm2RepositoryRoot
    return [ordered]@{
        ExecutablePath = Join-Path $root '.local/work/fm2/out/build/win-amd64-release/fm2.exe'
        GameDataRoot = Join-Path $root 'extracted'
        UserDataRoot = Join-Path $root '.local/user'
        ContentRoot = ''
        VSync = $true
        Fullscreen = $false
        Width = 1280
        Height = 720
        MaxFps = 60
        Scale = 1
    }
}

function Read-Fm2LauncherSettings([string]$Path) {
    $settings = Get-Fm2LauncherDefaults
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $saved = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in @($settings.Keys)) {
            if ($saved.ContainsKey($key)) { $settings[$key] = $saved[$key] }
        }
    }
    return $settings
}

function Save-Fm2LauncherSettings([string]$Path, [System.Collections.IDictionary]$Settings) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($Path)))) | Out-Null
    # Replace only after a complete JSON file is written.
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Settings | ConvertTo-Json))
    [IO.File]::Move($temporary, $Path, $true)
}

function Merge-Fm2RuntimeConfiguration {
    param([string]$Template, [System.Collections.IDictionary]$Values)
    if ($Template -match '(?m)^\s*\[') {
        throw 'The launcher needs a flat fm2.toml. Remove TOML sections before using it.'
    }
    $result = $Template
    foreach ($key in $Values.Keys) {
        if ($key -notmatch '^[a-z][a-z0-9_]*$') { throw "Invalid setting name: $key" }
        $result = [regex]::Replace($result, "(?m)^\s*$key\s*=.*(?:\r?\n|$)", '')
    }
    $result = $result.TrimEnd() + "`n"
    foreach ($key in $Values.Keys) {
        $value = $Values[$key]
        $literal = if ($value -is [bool]) { $value.ToString().ToLowerInvariant() } else { [string]$value }
        if ($literal -notmatch '^(true|false|[0-9]+)$') { throw "Invalid setting value: $key" }
        $result += "$key = $literal`n"
    }
    return $result
}

function New-Fm2LauncherPlan([System.Collections.IDictionary]$Settings) {
    foreach ($key in @('VSync', 'Fullscreen')) {
        if ($Settings[$key] -isnot [bool]) { throw "$key must be true or false." }
    }
    foreach ($key in @('Width', 'Height', 'MaxFps', 'Scale')) {
        if ($Settings[$key] -isnot [int] -and $Settings[$key] -isnot [long]) { throw "$key must be a whole number." }
    }
    if ($Settings.Width -lt 640 -or $Settings.Width -gt 8192 -or $Settings.Height -lt 480 -or $Settings.Height -gt 8192) {
        throw 'Window resolution must be between 640 x 480 and 8192 x 8192.'
    }
    if ($Settings.MaxFps -lt 0 -or $Settings.MaxFps -gt 1000) { throw 'FPS cap must be 0 (unlimited) through 1000.' }
    if ($Settings.Scale -notin 1, 2, 3) { throw 'Render scale must be 1, 2 or 3.' }
    $executable = [IO.Path]::GetFullPath($Settings.ExecutablePath)
    if ([IO.Path]::GetFileName($executable) -ine 'fm2.exe' -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw 'Select a built fm2.exe. The source release contains no executable.'
    }
    $buildRoot = Split-Path -Parent $executable
    $receiptPath = Join-Path $buildRoot 'build-provenance.json'
    $supportsCap = $false
    $supportsPixels = $false
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable
        if ($receipt.ContainsKey('features') -and $receipt.features -contains 'gpu_max_fps') {
            $gpu = @($receipt.artifacts | Where-Object path -EQ 'rexgpu-xenos.dll')
            $pluginPath = Join-Path $buildRoot 'rexgpu-xenos.dll'
            $supportsCap = $gpu.Count -eq 1 -and (Test-Path -LiteralPath $pluginPath -PathType Leaf) -and
                (Get-FileHash -LiteralPath $pluginPath).Hash -eq $gpu[0].sha256
        }
        if ($receipt.ContainsKey('features') -and $receipt.features -contains 'window_size_in_pixels') {
            $runtime = @($receipt.artifacts | Where-Object path -EQ 'rexruntime.dll')
            $runtimePath = Join-Path $buildRoot 'rexruntime.dll'
            $supportsPixels = $runtime.Count -eq 1 -and (Test-Path -LiteralPath $runtimePath -PathType Leaf) -and
                (Get-FileHash -LiteralPath $runtimePath).Hash -eq $runtime[0].sha256
        }
    }
    if ($Settings.MaxFps -ne 0 -and -not $supportsCap) {
        throw 'This build has no verified FPS limiter. Rebuild with the launcher sources, or choose Unlimited.'
    }
    if (-not $Settings.Fullscreen -and -not $supportsPixels) {
        throw 'This build scales window dimensions with Windows DPI. Rebuild with the launcher sources for exact pixel resolution.'
    }
    $gameRoot = Assert-Fm2GameInputs -GameDataRoot $Settings.GameDataRoot
    $userRoot = [IO.Path]::GetFullPath($Settings.UserDataRoot)
    if ((Test-Path -LiteralPath $userRoot) -and -not (Test-Path -LiteralPath $userRoot -PathType Container)) {
        throw 'The profile path is a file. Select a folder.'
    }
    foreach ($protected in @($gameRoot, $buildRoot)) {
        if ($userRoot -eq $protected -or $userRoot.StartsWith($protected.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Select a separate profile folder, outside the game and build folders.'
        }
    }
    $arguments = @("--game_data_root=$gameRoot", "--user_data_root=$userRoot")
    if ($Settings.ContentRoot) {
        $content = [IO.Path]::GetFullPath($Settings.ContentRoot)
        if (-not (Test-Path -LiteralPath $content -PathType Container)) { throw 'Content folder not found.' }
        $arguments += "--fm2_content_root=$content"
    }
    $configPath = Join-Path $buildRoot 'fm2.toml'
    $template = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        [IO.File]::ReadAllText($configPath)
    } else { [IO.File]::ReadAllText((Join-Path (Get-Fm2RepositoryRoot) 'fm2/fm2_runtime.toml')) }
    $values = [ordered]@{
        vsync = $Settings.VSync
        fullscreen = $Settings.Fullscreen
        window_width = $Settings.Width
        window_height = $Settings.Height
        draw_resolution_scale_x = $Settings.Scale
        draw_resolution_scale_y = $Settings.Scale
    }
    if ($supportsCap) { $values.gpu_max_fps = $Settings.MaxFps }
    else {
        # Do not retain a stale cap from a different GPU plugin.
        $template = [regex]::Replace($template, '(?m)^\s*gpu_max_fps\s*=.*(?:\r?\n|$)', '')
    }
    if ($supportsPixels) { $values.window_size_in_pixels = $true }
    return [pscustomobject]@{
        Executable = $executable
        WorkingDirectory = $buildRoot
        Arguments = $arguments
        UserDataRoot = $userRoot
        ConfigPath = $configPath
        RuntimeConfiguration = Merge-Fm2RuntimeConfiguration $template $values
        SupportsFpsCap = $supportsCap
        SupportsPixelResolution = $supportsPixels
    }
}

function Start-Fm2LauncherPlan($Plan) {
    if (Get-Process -Name fm2 -ErrorAction SilentlyContinue) { throw 'Close FM2 before starting another run.' }
    [IO.Directory]::CreateDirectory($Plan.UserDataRoot) | Out-Null
    $temporary = $Plan.ConfigPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, $Plan.RuntimeConfiguration)
    if (Test-Path -LiteralPath $Plan.ConfigPath) {
        Copy-Item -LiteralPath $Plan.ConfigPath -Destination ($Plan.ConfigPath + '.launcher-backup') -Force
    }
    [IO.File]::Move($temporary, $Plan.ConfigPath, $true)
    $start = [Diagnostics.ProcessStartInfo]::new($Plan.Executable)
    $start.WorkingDirectory = $Plan.WorkingDirectory
    $start.UseShellExecute = $false
    $start.Environment['FM2_SKIP_INTRO'] = '1'
    foreach ($argument in $Plan.Arguments) { $start.ArgumentList.Add($argument) }
    return [Diagnostics.Process]::Start($start)
}
