# FM2 graphical launcher

The Windows launcher uses PowerShell 7 and built-in WPF controls. It starts an
existing local build. It does not download game files or build the game.

After `tools/Build-Local.ps1` finishes, open `Launch FM2 Settings.bat`.
Select the built `fm2.exe`, your extracted game folder and your profile folder.
Use the same profile folder as your previous run to retain progress.
Content is an optional folder of legally obtained marketplace packages.
Opening the launcher does not start the game. **Save** remembers settings;
**Start FM2** saves them, writes the runtime configuration and starts FM2.
Escape closes the launcher. Enter activates Start; keyboard shortcuts and Tab
move through the controls.

Preferences live in `.local/launcher/settings.json`. You can use a separate
preferences file or supply initial paths:

```powershell
pwsh -NoProfile -STA -File .\tools\Launch-Graphical.ps1 `
  -ExecutablePath "D:\FM2-build\fm2.exe" `
  -GameDataRoot "D:\Games\FM2-extracted" `
  -UserDataRoot "D:\FM2-profile" `
  -SettingsPath "D:\FM2-launcher\settings.json"
```

## Graphics controls

| Control | Runtime key | Meaning |
|---|---|---|
| VSync | `vsync` | Existing SDK vertical-sync behavior |
| Fullscreen | `fullscreen` | Fullscreen at monitor size, or a window |
| Window resolution | `window_width`, `window_height` | Output window dimensions; does not change the guest video mode |
| Maximum FPS | `gpu_max_fps` | Host frame-swap ceiling, independent of VSync; 0 or Unlimited disables it |
| Render scale | `draw_resolution_scale_x`, `draw_resolution_scale_y` | Internal rendering at 1x, 2x or 3x per axis |

The FPS field also accepts whole numbers through 1000. Resolution accepts
`width x height`, from 640 x 480 through 8192 x 8192. The game can run below a
chosen ceiling. The limiter does not unlock the engine's frame rate or change
the guest refresh rate, game clock or physics settings.

1x is the tested default. Higher render scales are experimental: an earlier
2x test showed visual faults. The launcher does not fix those faults.
VSync and a lower FPS ceiling can both affect pacing; their combined behavior
still needs an owner-run game comparison on the launcher build.

The launcher preserves unrelated settings in the selected build's flat
`fm2.toml`. It replaces only its managed graphics keys. Before Start writes
that file, it saves the previous contents as `fm2.toml.launcher-backup`.
The command-line run script retains these graphics choices and changes its
own trace setting. Validation does not write configuration or profile files.

## FPS-cap build and checks

The public SDK pin remains the revision in `release/release-policy.json`.
The local builder applies `release/sdk-fps-cap.patch` while building the GPU
plugin, then reverses the patch to leave the SDK checkout clean. It records
the patch hash and `gpu_max_fps` feature in `build-provenance.json`.
The launcher checks that receipt against the actual GPU plugin hash before
accepting a nonzero cap. An older build can use Unlimited and the other
controls, but needs a rebuild for the new limiter.

The patch paces Xbox swap packets with a host steady clock and the existing
SDK sleep timer. It restarts the schedule after a late frame, retries early
wakeups, and resets when the cap changes or is disabled. Zero is the SDK
default. This does not modify vblank frequency.

Run configuration and source checks without starting FM2:

```powershell
pwsh -NoProfile -File .\tools\Test-Launcher.ps1
pwsh -NoProfile -File .\tools\Test-ReleaseWorkflow.ps1
pwsh -NoProfile -File .\tools\Test-RepositoryBoundary.ps1
pwsh -NoProfile -STA -File .\tools\Launch-Graphical.ps1 -RenderPreview "$env:TEMP\fm2-launcher.png"
```

`-ValidateOnly` returns a launch plan without opening the window or starting
the game. `-RenderPreview` renders the actual controls to a PNG without
showing a window. These checks do not prove in-game behavior.

To check native pacing, apply the patch to the pinned SDK checkout and build
its Release GPU plugin. Configure the host tests with `-G Ninja -DCMAKE_BUILD_TYPE=Release` and
`-DFPS_CAP_SDK_ROOT="D:/path/to/rexglue-sdk"`. The optional `frame_pacer_test`
uses that patched header, GPU plugin and runtime. It checks deferred TOML
loading, invalid caps, unchanged guest refresh, schedule reset and real timer
pacing at 30, 60 and 120 swaps per second. Reverse the patch after the check.
No game is started by this test.

The previously published `v0.1.0-alpha.1` source archive and checksum are
unchanged. They predate this launcher and FPS patch.
