#!/usr/bin/env bash
#
# Generate localsend-<version>-flutter-deps.tar.xz. Run on a networked host; see
# README.md. Needs on PATH: curl tar xz git rsync cargo, and the Flutter Linux
# toolchain (clang cmake ninja pkg-config, gtk3 + libayatana-appindicator3 dev).
#
#   ./generate-flutter-deps.sh 1.17.0 3.24.5
#
set -euo pipefail

PV="${1:?usage: generate-flutter-deps.sh <localsend-version> [flutter-version]}"
FLUTTER_VERSION="${2:-3.24.5}"

ROOT="$(pwd)"
WORK="${ROOT}/build-${PV}"
rm -rf "${WORK}"; mkdir -p "${WORK}/home"; cd "${WORK}"

export HOME="${WORK}/home"
export PUB_CACHE="${WORK}/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
mkdir -p "${PUB_CACHE}"

echo "==> [1/8] Fetch Flutter SDK ${FLUTTER_VERSION}"
curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
  | tar xJ -C "${WORK}"                        # -> ${WORK}/flutter
export PATH="${WORK}/flutter/bin:${PATH}"
git config --global --add safe.directory "${WORK}/flutter"

echo "==> [2/8] Fetch localsend v${PV}"
curl -fsSL "https://github.com/localsend/localsend/archive/refs/tags/v${PV}.tar.gz" \
  | tar xz -C "${WORK}"                        # -> ${WORK}/localsend-${PV}
SRC="${WORK}/localsend-${PV}"

echo "==> [3/8] Apply upstream FOSS strip (drops proprietary in-app-purchase / donations)"
# The script cd's into app/ itself, so run it from the repository root. Its path
# moved between releases: v1.17.0 has scripts/, newer has support/scripts/.
( cd "${SRC}" && { sh scripts/remove_proprietary_dependencies.sh 2>/dev/null \
                   || sh support/scripts/remove_proprietary_dependencies.sh; } )
# keep a pristine (post-strip) copy of lib/ to diff against after codegen
cp -a "${SRC}/app/lib" "${WORK}/lib-pristine"

echo "==> [4/8] Resolve Dart deps"
cd "${SRC}/app"
flutter --no-version-check config --no-analytics >/dev/null 2>&1 || true
flutter --no-version-check pub get

echo "==> [5/8] Run build_runner (dart_mappable codegen)"
# dart_mappable + analyzer race on multiple cores and fail with "Invalid
# argument(s): Missing library"; pin build_runner to a single core.
TASKSET="${TASKSET:-}"
if [ -z "${TASKSET}" ] && command -v taskset >/dev/null; then
  TASKSET="taskset -c 0"
fi
${TASKSET} flutter --no-version-check pub run build_runner build -d

# cargokit (rhttp's Rust build) drives the toolchain through rustup and honours the
# app's rust-toolchain.toml pin (1.84.1), which the runner's rustup won't have. Shim
# rustup to the plain system cargo — the vendored bundle is toolchain-agnostic.
mkdir -p "${WORK}/shim"
cat > "${WORK}/shim/rustup" <<'SH'
#!/bin/sh
case "$1" in
  toolchain) [ "$2" = list ] && echo "stable-x86_64-unknown-linux-gnu (default)"; exit 0 ;;
  target)    echo "x86_64-unknown-linux-gnu"; exit 0 ;;
  run)       shift 2; exec "$@" ;;
  *)         exit 0 ;;
esac
SH
chmod +x "${WORK}/shim/rustup"
export PATH="${WORK}/shim:${PATH}"

# Flutter's APPLY_STANDARD_SETTINGS forces -Werror; a newer libayatana-appindicator
# marks app_indicator_new() deprecated and breaks the tray_manager plugin. The ebuild
# patches this out; do the same here so the build finishes and fully populates the cache.
sed -i 's/-Wall -Werror/-Wall/' "${SRC}/app/linux/CMakeLists.txt"

echo "==> [6/8] Full Linux build (populates pub-cache with flutter_tools + cargokit deps)"
# Required even though the artifacts are discarded: the first `flutter build linux`
# is what pulls flutter_tools' deps AND cargokit's build_tool deps (convert, github,
# toml, version, ...) into pub-cache. Without it the bundle is incomplete and the
# ebuild's offline build fails.
flutter --no-version-check build linux --release

echo "==> [7/8] Assemble bundle"
DEPS="${WORK}/localsend-${PV}-flutter-deps"
rm -rf "${DEPS}"; mkdir -p "${DEPS}/generated-lib"
cp -a "${PUB_CACHE}" "${DEPS}/pub-cache"
cp "${SRC}/app/pubspec.lock" "${DEPS}/pubspec.lock"
# generated-lib = files that build_runner added to or changed in lib/
while IFS= read -r rel; do
  mkdir -p "$(dirname "${DEPS}/generated-lib/lib/${rel}")"
  cp -a "${SRC}/app/lib/${rel}" "${DEPS}/generated-lib/lib/${rel}"
done < <(
  cd "${SRC}/app/lib"
  find . -type f | sed 's#^\./##' | while read -r rel; do
    if [ ! -e "${WORK}/lib-pristine/${rel}" ] \
       || ! cmp -s "${rel}" "${WORK}/lib-pristine/${rel}"; then
      printf '%s\n' "${rel}"
    fi
  done
)
echo "    generated files: $(find "${DEPS}/generated-lib" -type f | wc -l)"
# vendored Rust crates for the rhttp plugin
RHTTP_RUST="$(dirname "$(find "${PUB_CACHE}/hosted" -path '*/rhttp-*/rust/Cargo.toml' | head -1)")"
( cd "${RHTTP_RUST}" && cargo vendor --locked "${DEPS}/rust-vendor" >/dev/null )

echo "==> [8/8] Pack"
cd "${WORK}"
tar -c "localsend-${PV}-flutter-deps" | xz -T0 -6 > "${ROOT}/localsend-${PV}-flutter-deps.tar.xz"
cd "${ROOT}"
OUT="localsend-${PV}-flutter-deps.tar.xz"
ls -lh "${OUT}"
echo "SIZE=$(stat -c%s "${OUT}")"
echo "BLAKE2B=$(b2sum "${OUT}" | cut -d' ' -f1)"
echo "SHA512=$(sha512sum "${OUT}" | cut -d' ' -f1)"
echo "==> Done: ${OUT}"
