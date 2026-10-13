# Third-party software notices

The FM2 source release does not contain third-party binaries or generated game
translation. It references and locally builds the following direct dependency:

- [ReXGlue SDK](https://github.com/Alexbeav/rexglue-sdk), pinned by
  `release/release-policy.json`, is licensed under the BSD 3-Clause License.
  It includes or links components under their own terms and contains code
  derived from [Xenia](https://github.com/xenia-project/xenia), also under the
  BSD 3-Clause License.

The pinned SDK checkout is the authority for its complete dependency list and
license texts. Anyone who redistributes SDK files or locally produced binaries
must preserve the notices and satisfy the licenses shipped with that exact SDK
source. The FM2 source packager does not package those files.

## Launcher branding image

`tools/assets/fm2-logo.png` is the FM2 logo screenshot supplied by the project
owner and approved for the launcher package. The Forza Motorsport 2 logo and
trademarks belong to their respective owners. This image is not covered by
the project's BSD 3-Clause source-code license. Its inclusion does not grant
rights to Forza Motorsport 2 or its trademarks.

## Owner-supplied game screenshots

The twelve JPEG images under `docs/screenshots/` were supplied by the project
owner for the README. They show Forza Motorsport 2 during release testing.
Game artwork, vehicle branding and other third-party content shown in them
belong to their respective owners. These images are not covered by the
project's BSD 3-Clause source-code license.
