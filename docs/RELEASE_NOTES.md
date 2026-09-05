# Release notes

## v0.1.0-alpha.1 candidate

This first experimental source release provides a builder-first path for the
European retail version of Forza Motorsport 2. It validates the user's Xbox
executable, builds the pinned continuation-aware ReXGlue SDK, generates the
recompiled module locally, and builds and launches FM2 in isolated local state.

The owner operated menus and live racing on an earlier development build.
A longer telemetry run used a local SDK patch.
Race completion, save/reload, progression, and DLC car availability remain outside the tested release boundary.
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
