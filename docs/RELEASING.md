# Builder-first release process

This file is the authority for FM2 release contents and review. The only
public artifact currently authorized by the repository is a deterministic
source archive plus its SHA-256 checksum. Do not publish an artifact until the
project owner approves its exact contents and workflow.

## Public artifact boundary

The source archive is built from the exact paths in
[`release/source-files.txt`](../release/source-files.txt). The policy and
validated game executable identity are machine-readable in
[`release/release-policy.json`](../release/release-policy.json).

The archive must not contain:

- game files, disc images, XEX files, marketplace packages, or Xbox system
  files;
- generated C++ translation under `fm2/generated`;
- FM2 executables, SDK binaries, object files, or debug symbols;
- saves, user data, shader caches, logs, dumps, or captures; or
- local build and dependency directories.

`tools/Test-RepositoryBoundary.ps1` rejects files outside the source allowlist
and rejects forbidden paths, extensions, sizes, and executable or Xbox package
magic. Ignored files are never package inputs.

## Create a review candidate

Use a clean reviewed commit for a final candidate:

```powershell
pwsh -File .\tools\Test-RepositoryBoundary.ps1
pwsh -File .\tools\New-SourceRelease.ps1 -Version 0.1.0-alpha.1
```

For an internal preview of uncommitted work, add `-AllowDirty`. The embedded
`SOURCE-PROVENANCE.json` records that the worktree was dirty. A dirty candidate
is not publishable.

The packager writes a ZIP with sorted entries, no compression, and a fixed
entry timestamp. It also writes `<archive>.sha256`. Identical source bytes,
version, repository URL, and commit identity produce identical archives.

## Review gate

Before publication:

1. Run the boundary check from a clean checkout of the candidate commit.
2. Create the archive twice in separate output directories and compare hashes.
3. Inspect every archive entry and `SOURCE-PROVENANCE.json` against the source
   allowlist.
4. Confirm `project_worktree_dirty` is `false`, and confirm the recorded FM2
   and SDK commits.
5. Run `tools/Test-ReleaseWorkflow.ps1` and the host tests in [Build notes](../BUILD-NOTES.md).
6. Extract the archive into a directory outside every Git checkout.
7. Run `tools/Build-Local.ps1 -ValidateOnly` there with the required game dump.
8. Complete the full archive build there and inspect `build-provenance.json` beside the executable.
9. After operator approval, test race completion and save/reload on that exact build.
10. Before any DLC support claim, follow the [content diagnostic procedure](CONTENT.md) and inspect visible cars.
11. Present the archive entries, hashes, test evidence, and proposed release
   text to the project owner. Publication requires explicit approval.

## User-side build

The source archive does not contain a disc or ZIP extractor. The user extracts
a legally obtained copy of the game, then runs:

```powershell
pwsh -File .\tools\Build-Local.ps1 -GameDataRoot "D:\Games\FM2-extracted"
pwsh -File .\tools\Run-Local.ps1 -GameDataRoot "D:\Games\FM2-extracted"
```

The builder verifies `default.xex` by size and SHA-256, clones the configured
ReXGlue commit with its submodules, builds the SDK, copies allowlisted source
into `.local/work`, generates translation there, and builds FM2. It writes
`build-provenance.json` beside the local executable. No game input or generated
translation is uploaded.

The launcher sources add a small, allowlisted FPS-cap patch to the pinned SDK
build. The builder records its hash and feature in the receipt, then restores
the SDK sources. See [FM2 launcher](LAUNCHER.md) for this build's controls and
checks. The published `v0.1.0-alpha.1` archive predates these changes.

The builder reads source identity before the SDK build.
Without a local `.git` entry, it requires `SOURCE-PROVENANCE.json` and matching hashes for every allowlisted file.
A parent Git repository never supplies archive identity.
For source edits, use a Git checkout instead of changing an extracted release archive.

Before a rebuild, the builder preserves `.local/work` under `.local/previous-builds`.
The builder permits its `.local` output directory during preflight.
The default boundary test remains strict for source archives and rejects that directory.
The local telemetry launcher is ignored and never enters a source archive.

The run script passes `.local/user` as the user-data root. Release testing does
not modify an existing ReXGlue profile in the user's Documents folder.

The build requires Windows AMD64, Git, CMake 3.25 or newer, Ninja, and Clang.
LLVM 22 targeting the MSVC ABI is validated. The builder rejects a
MinGW/libc++ target because its C++ ABI is incompatible with the pinned SDK.
