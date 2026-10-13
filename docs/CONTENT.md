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

## User-data location

The runner uses `.local/user` by default.
`-UserDataRoot` selects a different directory for profiles, saves, installed content, and caches.
The runner does not migrate existing data into that directory.
A new empty directory starts a separate profile.

The candidate's long extraction paths coincided with two installation failures.
The local repair used a shorter isolated path and retained the original data.
This repair corrected file completeness but did not prove in-game car availability.

Before a migration, close FM2 and preserve the original directory.
Use a short absolute path for `-UserDataRoot`.
Use `-ValidateOnly` with the run command to inspect its paths and configuration without launching FM2 or writing files.

## Collect a guest DLC trace

This procedure launches FM2 and requires operator approval.
The trace records the guest game's loading results without changing guest registers or license bits.

1. Build the source candidate with `tools/Build-Local.ps1`.
2. After approval, launch with the content directory and `-TraceContent`:

```powershell
pwsh -File .\tools\Run-Local.ps1 `
  -GameDataRoot "D:\Games\FM2-extracted" `
  -UserDataRoot "D:\FM2-user" `
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
| Special-edition marker lookup | Package index and file attributes, logged under the legacy `descriptor` label |
| Mount | Package index and guest mount result |

These stages can locate a loading failure.
They do not directly prove license-script application or visible cars.
The repaired installation passed enumeration and content opens in the September 5 operator run.
The base game then rejected all four packages because they lacked its special-edition marker.
The private TU4 preview removes this filter and uses separate hooks.
The owner reached its dealer screens and saw the Clio Renaultsport 197.
Its trace recorded successful opens and provider registration for all four packages.
The trace is off by default.
The runtime configuration key is `fm2_content_trace`.
The pinned SDK loads this configuration after command-line values.
The corrected runner writes the requested trace value into the runtime copy of `fm2.toml`.
The original `rc.1` runner does not contain this correction.
No game launch occurred during the corrected runner's synthetic tests.

## Private TU4 offline car-pack compatibility

This feature exists only in the ignored local TU4 preview, not the source release candidate.
It does not change the importer or claim to recover Xbox entitlements.
The original containers contain one license record each, with bit 1 and no bit 2.
The pinned importer retains bit 1 only when that record's flags are nonzero.
The resulting installed masks are 0, 1, 0, and 1 for the packages below.
The pinned runtime returns these masks unchanged to FM2's content-open call.
Its global `license_mask` configuration does not override this call.

The private hook adds bits 1 and 2 to the returned mask after a successful content open.
The TU4 script loader processes each set bit separately, so mask 3 selects both existing SQL files.
It requires `fm2_tu4_offline_car_packs = true` and an exact match with one of the four known package names.
The compiled default is false. The private preview configuration explicitly enables it.
Unknown packages, other content types, failed opens, and invalid record bounds retain their original result.
The hook preserves other access bits and does not write packages, installed headers, game databases, or profiles.
Normal gameplay can still update the separate test profile.

| Supplied content | Package prefix | Stored mask | Car entries | Useful dealer test |
|---|---|---|---|---|
| Nissan content, including Peugeot 908 assets | `1E18E526` | 0 | 4 | 2007 Nissan Sentra SE-R |
| December car pack | `323B57FE` | 1 | 11 | 2008 Audi R8 |
| September car pack | `9AF54AC6` | 0 | 11 | 2007 Porsche 911 GT3 RS |
| February-named package with the March roster | `DF292DCF` | 1 | 13 | 2008 Mitsubishi Lancer Evolution X |

The audit compared all 48 installed payload files with their original container bytes. All files matched.
All eight ZIPs passed CRC tests, and the base database plus four DLC merge databases passed SQLite integrity tests.
An in-memory fixture combined the base database and DLC merge rows, then ran the original license scripts.
The stored masks activated only car IDs 635 and 1024: the Clio Renaultsport 197 and Peugeot 207 Super 2000.
The compatibility masks activated all 39 supplied car entries and added them to the stock list.
A second application of the scripts produced no duplicate stock-list rows.
This fixture does not reproduce the full guest database loader or establish in-game availability, rendering, or driving.
The owner subsequently confirmed the four dealer test cars, one from each supplied package.
Race tests and individual coverage of every car remain pending.

The September 5 session at 21:42 contains four `offline_compatibility` records and four registered masks of `00000003`.
The private launcher requires the matching build receipt, native 1x resolution, tracing, and the enabled compatibility configuration.
The prior working preview and receipt remain in the local `pre-offline-dlc-20260905` backup.
This scope covers the four supplied car packs, not every historical FM2 download or track expansion.
