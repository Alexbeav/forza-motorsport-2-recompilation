# Marketplace content

The importer extracts operator-supplied FM2 marketplace packages into local ReXGlue user data.
The source release does not include packages or grant access to their contents.
The importer does not replace the game executable or change license masks to unlock cars.

## What an installation message means

The importer reads the STFS container header, content type, and Title ID before extraction.
STFS is the Xbox package format.
These tests do not authenticate the Microsoft signature.

For existing content, the importer reads the installed header and compares its package name, content type, and FM2 Title ID.
It also requires a nonempty readable content directory.
It preserves incomplete installations and reports them instead of silently overwriting files.
This structural test does not establish ZIP integrity or in-game activation.

A stored license mask is a set of bits that the runtime returns to the game when requested.
The supplied car packs contain separate database scripts for different bits.
Shared car assets alone do not establish full-pack access.
The importer reports the stored mask but does not change it.

See [Current status](STATUS.md) for the inspected packages and remaining limitations.

## Collect a guest DLC trace

This procedure launches FM2 and requires operator approval.
The trace records the guest game's loading results without changing guest registers or license bits.

1. Build the source candidate with `tools/Build-Local.ps1`.
2. After approval, launch with the content directory and `-TraceContent`:

```powershell
pwsh -File .\tools\Run-Local.ps1 `
  -GameDataRoot "D:\Games\FM2-extracted" `
  -ContentRoot "D:\Games\FM2-content" `
  -TraceContent
```

3. Open the car selection or dealer screen.
4. Look for a known car from each supplied pack.
5. Exit FM2 and preserve `fm2.log` beside the executable.

The `FM2_DLC_TRACE` records contain these stages:

| Stage | Recorded result |
|---|---|
| Enumerator creation | Return code, handle, and requested buffer size |
| Enumeration | Return code and package count |
| Content open | Package index and return code |
| Descriptor lookup | Package index and lookup result |
| Mount | Package index and guest mount result |

These stages can locate a loading failure.
They do not directly prove license-script application or visible cars.
The trace is off by default.
The runtime configuration key is `fm2_content_trace`.
