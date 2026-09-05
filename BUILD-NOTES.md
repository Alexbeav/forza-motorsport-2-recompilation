# FM2 build notes

## Pinned Windows toolchain

Build the ReXGlue SDK and FM2 with the same MSVC C++ ABI. The validated build
uses LLVM 22.1.8: the SDK uses the `clang++` driver targeting
`x86_64-pc-windows-msvc`, and FM2 uses `clang-cl`. Do not mix this SDK build
with a MinGW/libc++ project build.

The pinned public SDK fork is commit
[`f16992c`](https://github.com/Alexbeav/rexglue-sdk/commit/f16992c92e610c2d71773994436b442d9946f4e1).
It contains continuation-alias handling required by FM2's complete function
map and current Windows toolchain fixes. Stock ReXGlue 0.10.0 does not generate
this map correctly.

The builder-first path installs the SDK under `.local/sdk-install`, copies the
allowlisted source into `.local/work`, generates game-derived translation
there, and builds FM2 under:

```text
.local/work/fm2/out/build/win-amd64-release
```

The builder changes the manifest only inside `.local/work` to reference the user's game directory.
The tracked manifest stays machine-neutral.
Before a rebuild, the builder moves the previous workspace into `.local/previous-builds`.
The builder does not delete the previous executable, generated source, or run logs.

The builder records source identity before compilation and hashes the copied source files.
An unchanged source archive supplies its identity through `SOURCE-PROVENANCE.json`, without a project Git checkout.
Git remains necessary for the SDK checkout.
The build receipt records the archive identity, source hashes, SDK commit, and artifact hashes.

## Windows math compatibility

Current Clang/SIMDe output can reference the C23 functions `roundevenf` and
`roundeven`, which are absent from the current Windows UCRT. The small Windows
compatibility implementation in `fm2/src/compat_math.cpp` supplies those two
symbols. It does not alter generated game code.

## Validated generation and build

On 2026-09-03, code generation from the validated European retail executable
completed in approximately 148 seconds. A subsequent LLVM 22 `clang-cl`
release build completed and produced `fm2.exe` with SHA-256:

```text
1A378575356A89AE5E994CEEA5F89D55AFAC86085F909863DD1B1CA852B60E4C
```

That hash identifies the retained dirty development build, not a public
binary artifact. Public releases are source-only.

The September 4 telemetry executable used the SDK pin plus a local SDK patch.
It is not the clean pinned-SDK release candidate.
See [Current status](docs/STATUS.md) for gameplay evidence and its limits.

## Headless regression tests

These tests do not launch FM2 or require game assets:

```powershell
pwsh -NoProfile -File .\tools\Test-ReleaseWorkflow.ps1
cmake -S tests -B .local/host-tests -G Ninja -DCMAKE_CXX_COMPILER=clang-cl
cmake --build .local/host-tests
ctest --test-dir .local/host-tests --output-on-failure
```

The release tests cover archive identity, parent Git repositories, changed source files, deterministic archives, and native command failures.
The content tests cover missing files, incomplete headers, wrong identities, empty content, and stored license masks.
Both test suites preserve their fixtures in the host temporary directory.
