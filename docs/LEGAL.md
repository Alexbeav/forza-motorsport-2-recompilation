# License and content boundary

The independently authored source code, scripts, configuration, and
documentation in this repository are licensed under the BSD 3-Clause License,
unless a file states otherwise. The complete license text is in
[`LICENSE`](../LICENSE).

That license grant is limited to material the project is entitled to license.
It does not grant rights to Forza Motorsport 2, Xbox software, game assets,
Xbox executable files, saves, disc images, downloadable content, trademarks,
or other third-party material. Users must provide their own legally obtained,
extracted game data and optional marketplace content.

The launcher branding image at `tools/assets/fm2-logo.png` is separately
identified in [Third-party notices](../THIRD_PARTY_NOTICES.md). It is excluded
from the project's BSD source-code license grant.

## Generated translation

ReXGlue generates C++ from the user-supplied Xbox executable. Generated
translation is created only on the user's computer under `fm2/generated` or
`.local/work/fm2/generated`. It is excluded from source archives and version
control. This project makes no license grant for that generated output.

Public releases use the builder-first process in
[`RELEASING.md`](RELEASING.md). They do not include a precompiled FM2
executable. Shipping a linked binary would require a separate rights and
dependency-license review; the release scripts do not provide that path.

## Dependencies

The local builder obtains the pinned ReXGlue SDK source and builds it on the
user's computer. ReXGlue and its dependencies retain their own licenses and
notices. See [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

This document records the project's release policy. It is not legal advice.
