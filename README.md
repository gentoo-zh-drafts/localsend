# localsend build dependencies

Prebuilt build-time dependency bundles for `net-misc/localsend` (from-source
Flutter build) in the [gentoo-zh overlay](https://github.com/gentoo-zh/overlay).

Each release `<version>` ships `localsend-<version>-flutter-deps.tar.xz`,
containing everything needed for a fully offline build:

- `pub-cache/` — resolved Dart/Flutter pub dependencies
- `generated-lib/` — `build_runner` (dart_mappable) generated sources
- `pubspec.lock` — lockfile for the FOSS build variant
- `rust-vendor/` — vendored Rust crates for the `rhttp` plugin (cargokit)

Generated from the upstream `v<version>` tag. Not for direct consumption.