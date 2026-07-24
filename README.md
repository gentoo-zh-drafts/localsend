# localsend build deps

Offline build inputs for `net-misc/localsend` (from-source) in the gentoo-zh overlay.
Each release ships `localsend-<version>-flutter-deps.tar.xz` containing `pub-cache/`,
`generated-lib/` (build_runner output), the FOSS `pubspec.lock`, and `rust-vendor/`
(the rhttp plugin's crates).

## Regenerate

Actions → **Generate flutter-deps** → Run workflow → enter the version. Or locally:

    ./generate-flutter-deps.sh 1.17.0 3.24.5

It prints the size/BLAKE2B/SHA512 for the ebuild `Manifest`.

## Non-obvious bits (handled in the script)

- `flutter build linux` is run only to pull `flutter_tools` + cargokit `build_tool`
  deps into the pub-cache; without it the offline build fails on missing packages.
- `build_runner` (dart_mappable) races on multiple cores; pinned to a single core.
- `pubspec.lock` is taken after the FOSS strip, so it matches the stripped pubspec.
