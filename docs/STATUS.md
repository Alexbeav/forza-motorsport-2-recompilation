# Current status

## Launcher build — 2026-10-13

The owner confirmed recurring wavy graphics at 2x internal scale on 2026-10-14.
The launcher now marks 2x as buggy and 3x as untested. Native 1x remains the default.

On 2026-10-14 the owner reported that the game window exceeded the selected
resolution. The launcher passed 2560 x 1440 to SDK settings defined in logical
units; the running window used 150% DPI. A separate runtime patch adds explicit
pixel dimensions, which the launcher now requires for windowed mode.
Native checks retain 2560 x 1440 at 100%, 125%, 150% and 200% DPI. The rebuilt
candidate still needs the owner to verify its actual game client area after restart.

The graphical launcher and independent host FPS-cap patch passed settings,
source-boundary, packaging and native pacing checks. The selected GPU plugin
consumed its cap from TOML without changing the guest refresh setting.
The private test candidate reuses the released-source FM2 executable with a
rebuilt GPU plugin. Its profile copy matched all 73 files at staging.
No game was started by these checks. An owner run of this candidate remains
pending. See [FM2 launcher](LAUNCHER.md) for controls and limitations.

The earlier public release test completed a race, arcade unlocks, career
startup and save/reload, as reported by the owner on 2026-10-13. The normal
run had no reported hiccups without a debugger. This does not establish
extended stability or qualify the newer FPS-cap candidate.

Launcher review: 2026-10-13. Earlier source and content review: 2026-09-05 on Windows AMD64 with D3D12.
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
| September 5 candidate | The owner reached the dealer screens with the clean-SDK candidate. Two packages failed extraction under its long user-data path. |
| Resolution test | The owner reported stained-glass corruption at 2x internal scaling. The local launcher returned to 1x. |
| Local content repair | A shorter isolated root contains all four packages with matching headers and 52 matching payload/header hashes. All eight ZIPs passed CRC. |

Each local build writes `build-provenance.json` beside its executable.
That receipt identifies the exact source, SDK, and output files.
The September 3 retained developer build, September 4 telemetry build, and later source candidates are distinct artifacts.

## Current boundary and known issues

- The owner reached the September 5 candidate menus but did not complete its race and save/reload tests.
- Internal scaling above 1x failed visual correctness. No higher-resolution configuration passed testing.
- The owner confirmed a representative car from each of the four supplied packs in the private TU4 preview.
- The showroom turns black when the UI finishes its right-stick fade and recovers after stick release. This owner-reported issue remains open.
- The installed Nissan and September headers have zero license masks.
- The installed December and February headers contain only the sampler bit.

- The earlier automated smoke capture was black, but the later owner-operated
  run confirmed main-menu rendering, navigation, race loading, and live driving.
- The September 5 candidate's race completion, saving and progression were
  untested then. The October 13 public release test covers the bounded route
  above; long-run stability remains unqualified.
- The runtime reports missing optional audio banks and language directories in
  the tested extracted tree. The effect beyond startup is not yet known.
- Some GPU resolve operations and kernel services remain incomplete or stubbed.
- Online services are outside the tested scope.

The telemetry run does not establish equivalent behavior with the unchanged SDK pin.
The September 5 trace enumerated and opened all four repaired packages successfully.
The base executable then rejected each package at its `SpecialEditionDLCOnly.txt` file-attribute test.
Static inspection identified this gate in the original loader. None of the four packages contains that marker.
The candidate's long extraction paths are a likely cause of its two installation failures, not a proven explanation for every missing car.
The local repair preserved the prior profile and files. The later TU4 operator test established partial activation, as described below.

## European TU4 work

The supplied European update matches Title ID `4D5307EA` and Media ID `3E3180AE`.
Its source-signature digest matches the retained base executable.
The headless SDK loader applied the update and reported version `0x00000403`, from base version `0x00000003`.
All 78 files in the update's media archive passed CRC tests.
The patched image no longer contains the special-edition marker filter.

TU4 changes code addresses and the DLC loader. The existing release candidate is not a TU4 build.
Local TU4 work uses an isolated game copy, function map, hooks, and build directory.
The original game, release candidate, and profile remain intact.
The isolated TU4 build completed with the pinned SDK and no unresolved code-generation targets.
Static tests cover ten relocated hooks, fiber-switch semantics, three continuation owners, native resolution, and DLC tracing.
The headless runtime read the full update archive through `update:\media.zip`.
The content host test and all 21 release workflow assertions passed.
All 66 copied profile, content, and cache files matched their originals.
The owner tested the first TU4 preview twice. Both runs stopped during startup at the unregistered callback `0x8262D418`.
The callback address came from guest instructions, not a data table. The original pointer scan missed this construction.
The local repair extends the scan to instruction-built addresses and tests this callback's boundary, body, and registration.
The review also found three callbacks with Xbox vector instructions that the conservative decoder did not recognize.
Those callbacks now have explicit boundaries in the private TU4 map.
The repaired preview built successfully and passed the static regression and launcher preflight without a game launch.
The owner subsequently reached the dealer screens with the repaired preview and saw the Clio Renaultsport 197, but not the Audi R8.
That run enumerated all four packages, opened them successfully, and registered all four filesystem providers.
Its returned masks were 0, 1, 0, and 1. The December mask enabled only its Clio sampler script.

The offline compatibility preview includes an opt-in, package-specific access hook.
It adds both car-access bits to successful content-open results without changing stored licenses or package files.
The build, two host tests, TU4 hook tests, and launcher preflight passed without a game launch.
The policy test contains 127 assertions for known packs, disabled policy, failed opens, unknown content, retained bits, and record bounds.
All 48 installed payload files matched their original container bytes. All eight ZIPs passed CRC tests.
The original license scripts activated all 39 supplied car entries in an in-memory database fixture, with no duplicate stock-list rows.
The original masks activated only the Clio and Peugeot 207 in that fixture.
This fixture is not a guest runtime test.
The subsequent owner session at 21:42 on September 5 opened and registered all four packages with mask `00000003`.
The owner confirmed the Audi R8, Mitsubishi Lancer Evolution X, Porsche 911 GT3 RS, and Nissan Sentra SE-R in the dealers.
This establishes representative visibility across all four packs, not a separate visual and driving test of every car.
Full car-loading coverage, driving, and save/reload still need operator testing.
The package and profile hash audit found no changes during this repair.
These TU4 changes remain private local work. The source release workflow does not yet build the TU4 target.

The confirmed build is `FC1ADDA0378F2E43CB914B2452723F5474DAADBDD0696FDE5B00E7FF62DF91BD`.
Its evidence remains under `.local/tu4-20260905/evidence/dlc-confirmed-20260905-214230`.
The corpus records this milestone in `FM2_TU4_DLC_EVIDENCE_2026-09-05.md`.

## Showroom fade investigation

The owner reports normal car viewing until the UI fade completes during right-stick camera movement.
At that point the entire screen turns black. Stick release restores the scene.
The game scripts explicitly send `FadeOutObjects` during held input and `FadeInObjects` after the input returns to rest.
The `ObjectFader` behavior responds through native `fadeOutDuration` and `fadeInDuration` calls.
This static evidence identifies the transition but does not establish why the full image disappears.
The preserved session log contains no frame-level capture of the transition.
The next diagnostic route needs matched visible, fully faded, and restored frames with corresponding GPU and fade-state evidence.
That runtime test requires owner approval. No fade bypass, GPU change, or resolution change occurred in this investigation.

The first candidate runner supplied tracing on the command line, but its runtime configuration disabled that value afterward.
The corrected runner writes the requested trace value into the runtime configuration.
These launcher and configuration corrections postdate the `rc.1` archive and need a new source candidate before publication.

The [content diagnostic procedure](CONTENT.md) separates file inspection from guest loading and activation.
The [release process](RELEASING.md) requires a clean source archive and a build outside a Git checkout.
Publication requires owner approval of that exact candidate.
Any initial publication remains an experimental source-only alpha.
