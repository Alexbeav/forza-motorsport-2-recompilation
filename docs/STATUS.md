# Current status

Last source and content review: 2026-09-05 on Windows AMD64 with D3D12.
This document owns the tested behavior and its limits.

## Test evidence

| Area | Validated result |
|---|---|
| Code generation | ReXGlue commit `f16992c` generated the full continuation-aware function map in approximately 148 seconds. |
| Build | LLVM 22.1.8 with the MSVC ABI produced the FM2 host executable and runtime dependency set. |
| Startup | The runtime initialized, mounted the extracted game, loaded `default.xex`, and translated 1,658 cached shaders. |
| Bounded run | The rebuilt process remained alive for the 45-second automated smoke window and was then stopped by the operator. |
| Interactive rendering | On 2026-09-04 the owner confirmed the main menu and a live eight-car race. The ReXGlue overlay reported 59.9 guest FPS in the captured race frame. |
| Telemetry | A separate instrumented run recorded 21,600 stable-race guest frames near 59.9 guest FPS and ended normally. It used a local SDK patch. |
| Release regression tests | Tests cover archive provenance outside Git, changed payload rejection, deterministic packaging, repeated-build boundaries, and command failures. |
| Content regression tests | Tests cover installed-header identity, header size, empty content, and license-mask decoding without FM2. |
| Local content inspection | Four FM2 packages have readable payloads and matching headers in both tested user-data roots. All sixteen installed ZIP copies passed CRC checks. |

Each local build writes `build-provenance.json` beside its executable.
That receipt identifies the exact source, SDK, and output files.
The September 3 retained developer build, September 4 telemetry build, and later source candidates are distinct artifacts.

## Current boundary and known issues

- No operator tested gameplay on the September 5 source changes.
- In-game DLC activation and car availability remain unconfirmed.
- The installed Nissan and September headers have zero license masks.
- The installed December and February headers contain only the sampler bit.

- The earlier automated smoke capture was black, but the later owner-operated
  run confirmed main-menu rendering, navigation, race loading, and live driving.
- Race completion, saving, progression, and long-run stability have not been
  validated for this release candidate.
- The runtime reports missing optional audio banks and language directories in
  the tested extracted tree. The effect beyond startup is not yet known.
- Some GPU resolve operations and kernel services remain incomplete or stubbed.
- Online services are outside the tested scope.

The telemetry run does not establish equivalent behavior with the unchanged SDK pin.
The missing title update is an unresolved compatibility question, not a proven explanation for the missing DLC cars.

The [content diagnostic procedure](CONTENT.md) separates file inspection from guest loading and activation.
The [release process](RELEASING.md) requires a clean source archive and a build outside a Git checkout.
Publication requires owner approval of that exact candidate.
Any initial publication remains an experimental source-only alpha.
