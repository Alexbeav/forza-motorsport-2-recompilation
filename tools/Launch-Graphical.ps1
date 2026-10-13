[CmdletBinding()]
param(
    [string]$ExecutablePath,
    [string]$GameDataRoot,
    [string]$UserDataRoot,
    [string]$ContentRoot,
    [string]$SettingsPath,
    [string]$LogoScreenshot,
    [string]$RenderPreview,
    [switch]$ValidateOnly
)

. (Join-Path $PSScriptRoot 'Launcher.Common.ps1')
trap {
    if (-not $ValidateOnly -and -not $RenderPreview -and $IsWindows) {
        Add-Type -AssemblyName PresentationFramework
        [void][Windows.MessageBox]::Show($_.Exception.Message, 'FM2 launcher', 'OK', 'Error')
    }
    throw $_
}
if (-not $IsWindows) { throw 'The graphical launcher requires Windows and PowerShell 7.' }
if (-not $SettingsPath) { $SettingsPath = Join-Path (Get-Fm2RepositoryRoot) '.local/launcher/settings.json' }
$settings = Read-Fm2LauncherSettings $SettingsPath
foreach ($key in @('ExecutablePath', 'GameDataRoot', 'UserDataRoot', 'ContentRoot')) {
    if ($PSBoundParameters.ContainsKey($key)) { $settings[$key] = $PSBoundParameters[$key] }
}
if ($ValidateOnly) { New-Fm2LauncherPlan $settings; return }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Start the launcher with pwsh -STA.' }
Add-Type -AssemblyName PresentationFramework
$reader = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'Launcher.xaml'))
try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$controls = @{}
foreach ($name in @('Surface','HeaderArtwork','HeaderBrush','HeaderFallback','VSync','Fullscreen','Resolution','MaxFps','Scale','ScaleNote','ExecutablePath','GameDataRoot','UserDataRoot','ContentRoot','BrowseBuild','BrowseGame','BrowseUser','BrowseContent','Save','Start','Status')) {
    $controls[$name] = $window.FindName($name)
}
if (-not $LogoScreenshot) { $LogoScreenshot = Join-Path (Get-Fm2RepositoryRoot) '.local/launcher/fm2-logo-screenshot.png' }
if (Test-Path -LiteralPath $LogoScreenshot -PathType Leaf) {
    $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new([IO.Path]::GetFullPath($LogoScreenshot))
    $bitmap.EndInit()
    $bitmap.Freeze()
    # Display the main logo region; the supplied screenshot stays unmodified.
    $controls.HeaderBrush.ImageSource = $bitmap
    $controls.HeaderArtwork.Visibility = 'Visible'
    $controls.HeaderFallback.Visibility = 'Collapsed'
}
foreach ($preset in @('1280 x 720', '1600 x 900', '1920 x 1080', '2560 x 1440', '3840 x 2160')) { [void]$controls.Resolution.Items.Add($preset) }
foreach ($preset in @('Unlimited', '30', '60', '90', '120', '144', '165', '240')) { [void]$controls.MaxFps.Items.Add($preset) }
foreach ($preset in @('1x native · tested', '2x supersampling · buggy', '3x supersampling · untested')) { [void]$controls.Scale.Items.Add($preset) }
$controls.VSync.IsChecked = $settings.VSync
$controls.Fullscreen.IsChecked = $settings.Fullscreen
$controls.Resolution.Text = "$($settings.Width) x $($settings.Height)"
$controls.MaxFps.Text = if ($settings.MaxFps -eq 0) { 'Unlimited' } else { [string]$settings.MaxFps }
$controls.Scale.SelectedIndex = [int]$settings.Scale - 1
foreach ($key in @('ExecutablePath', 'GameDataRoot', 'UserDataRoot', 'ContentRoot')) { $controls[$key].Text = $settings[$key] }

function Read-Controls {
    $result = Get-Fm2LauncherDefaults
    foreach ($key in @('ExecutablePath', 'GameDataRoot', 'UserDataRoot', 'ContentRoot')) { $result[$key] = $controls[$key].Text.Trim() }
    $result.VSync = [bool]$controls.VSync.IsChecked
    $result.Fullscreen = [bool]$controls.Fullscreen.IsChecked
    if ($controls.Resolution.Text -notmatch '^\s*(\d+)\s*[x×]\s*(\d+)\s*$') { throw 'Enter a resolution such as 1920 x 1080.' }
    $result.Width = [int]$Matches[1]; $result.Height = [int]$Matches[2]
    $capText = $controls.MaxFps.Text.Trim()
    if ($capText -ieq 'Unlimited') { $result.MaxFps = 0 }
    elseif ($capText -match '^\d+$') { $result.MaxFps = [int]$capText }
    else { throw 'Enter an FPS cap from 1 through 1000, or choose Unlimited.' }
    $result.Scale = $controls.Scale.SelectedIndex + 1
    return $result
}

function Update-ScaleNote {
    $controls.ScaleNote.Text = if ($controls.Scale.SelectedIndex -eq 0) {
        'Native internal resolution. Window size is a separate setting.'
    } elseif ($controls.Scale.SelectedIndex -eq 1) {
        'Buggy: wavy / distorted graphics confirmed at 2x. Use 1x for normal play.'
    } else { 'Untested: 3x may also distort graphics. 2x has a confirmed wavy-graphics bug.' }
    $controls.ScaleNote.Foreground = if ($controls.Scale.SelectedIndex -eq 0) { '#A8A49C' } else { '#FFB35D' }
}
Update-ScaleNote
$controls.Scale.Add_SelectionChanged({ Update-ScaleNote })
$controls.Fullscreen.Add_Checked({ $controls.Resolution.IsEnabled = $false })
$controls.Fullscreen.Add_Unchecked({ $controls.Resolution.IsEnabled = $true })
$controls.Resolution.IsEnabled = -not $settings.Fullscreen
$controls.Status.Text = 'Settings are local. Opening this window does not start FM2.'

$controls.BrowseBuild.Add_Click({
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Filter = 'FM2 executable (fm2.exe)|fm2.exe'
    if ($dialog.ShowDialog($window)) { $controls.ExecutablePath.Text = $dialog.FileName }
})
foreach ($pair in @(@('BrowseGame','GameDataRoot'), @('BrowseUser','UserDataRoot'), @('BrowseContent','ContentRoot'))) {
    $field = $pair[1]
    $handler = {
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Select ' + $field
        if ($dialog.ShowDialog($window)) { $controls[$field].Text = $dialog.FolderName }
    }.GetNewClosure()
    $controls[$pair[0]].Add_Click($handler)
}
$controls.Save.Add_Click({
    try {
        $chosen = Read-Controls
        $null = New-Fm2LauncherPlan $chosen
        Save-Fm2LauncherSettings $SettingsPath $chosen
        $controls.Status.Text = 'Saved. FM2 has not started.'
    } catch { $controls.Status.Text = $_.Exception.Message }
})
$controls.Start.Add_Click({
    try {
        $chosen = Read-Controls
        $plan = New-Fm2LauncherPlan $chosen
        Save-Fm2LauncherSettings $SettingsPath $chosen
        $process = Start-Fm2LauncherPlan $plan
        $controls.Status.Text = 'FM2 started. Your selected profile is in use.'
        $window.Close()
    } catch { $controls.Status.Text = $_.Exception.Message }
})
$window.Add_PreviewKeyDown({ if ($_.Key -eq 'Escape') { $window.Close() } })

if ($RenderPreview) {
    # Render the actual WPF controls without showing a window or launching FM2.
    $surface = $controls.Surface
    $size = [Windows.Size]::new(864, 660)
    $surface.Measure($size); $surface.Arrange([Windows.Rect]::new($size)); $surface.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(864, 660, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($surface)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create([IO.Path]::GetFullPath($RenderPreview))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    return
}
[void]$window.ShowDialog()
