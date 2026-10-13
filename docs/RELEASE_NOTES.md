# Release notes

## v0.1.0-alpha.2

This experimental source release adds the Windows graphical launcher for
VSync, an independent maximum FPS setting, fullscreen, physical window
resolution and internal render scale. It remembers paths and graphics
preferences and preserves existing profiles when the same folder is selected.
The header uses the owner-supplied logo screenshot, identified separately in
[Third-party notices](../THIRD_PARTY_NOTICES.md).

The builder applies two source patches to the existing public SDK pin:
host frame-swap pacing and exact pixel window sizing. It records both patch
hashes in local build provenance and restores the SDK checkout afterward.
The owner confirmed the DPI correction and approved the logo header.
Native pacing checks cover 30, 60 and 120 FPS ceilings. A new bounded race
and controlled in-game cap/VSync comparison on this version remain pending.

1x is the tested rendering default. 2x has confirmed wavy/distorted graphics;
3x is untested. No FSR/upscaling implementation or fix for higher internal
scales is included. The earlier spontaneous race crash remains unexplained.

Public assets remain a source ZIP and SHA-256 checksum. No game executable,
generated translation, SDK binary, save or marketplace package is distributed.
The published v0.1.0-alpha.1 archive and checksum remain unchanged.

## v0.1.0-alpha.1

This first experimental source release provides a builder-first path for the
European retail version of Forza Motorsport 2. It validates the user's Xbox
executable, builds the pinned continuation-aware ReXGlue SDK, generates the
recompiled module locally, and builds and launches FM2 in isolated local state.

The owner operated menus and live racing on an earlier development build.
A longer telemetry run used a local SDK patch.
On 2026-10-13 the owner completed a bounded race, confirmed arcade unlocks,
started career and verified retained progress after save/reload. Prolonged
stability and full DLC coverage remain outside the tested release boundary.
See [Current status](STATUS.md) for the evidence and exact limits.

The source-archive builder reads packaged provenance without a project Git checkout.
It rejects changed archive payloads and preserves previous build workspaces.
Headless regression tests cover this workflow and installed-content metadata.

The importer accepts operator-supplied FM2 marketplace packages and reports incomplete installed files.
It reports stored license masks without treating file presence as proof of car availability.
Optional read-only guest diagnostics support the next operator-approved DLC test.
See [Marketplace content](CONTENT.md).

This release contains project source and build tooling only. It does not
contain game files, generated translation, saves, SDK binaries, marketplace
content, or a compiled FM2 executable.
