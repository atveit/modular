#!/usr/bin/env bash
# Verify that every object in a proposed iOS CompilerRT archive carries
# iOS (or iOS Simulator) Mach-O metadata.  This is metadata evidence only;
# it does not link, sign, install, or execute an app.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
archive="${MOJO_IOS_COMPILERRT_ARCHIVE:-${repo_root}/bazel-bin/KGEN/libCompilerRTIOSBootstrapHost.a}"
target_triple="${MOJO_IOS_RUNTIME_TRIPLE:-arm64-apple-ios17.0-simulator}"

log() {
  printf '[compilerrt-ios-static-metadata] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

case "${target_triple}" in
  *-simulator) expected_platform="IOSSIMULATOR" ;;
  *-ios*) expected_platform="IOS" ;;
  *) fail "MOJO_IOS_RUNTIME_TRIPLE is not an iOS device or Simulator triple: ${target_triple}" ;;
esac

command -v ar >/dev/null 2>&1 || fail "ar is required"
command -v vtool >/dev/null 2>&1 || fail "vtool is required for Mach-O platform inspection"
if [[ ! -f "${archive}" ]]; then
  log "SKIP: archive is unavailable: ${archive}"
  log "Build it with: ./bazelw build --config=build-mojo //KGEN:CompilerRTIOSBootstrapHost"
  exit 0
fi

inspect_dir="$(mktemp -d "${TMPDIR:-/tmp}/mojo-compilerrt-ios-static.XXXXXX")"
trap 'rm -rf "${inspect_dir}"' EXIT
archive_abs="$(cd "$(dirname "${archive}")" && pwd)/$(basename "${archive}")"

log "archive: ${archive_abs}"
log "target: ${target_triple}; expected Mach-O platform: ${expected_platform}"
ar -t "${archive_abs}"
(cd "${inspect_dir}" && ar -x "${archive_abs}")

shopt -s nullglob
members=("${inspect_dir}"/*.o)
(( ${#members[@]} > 0 )) || fail "archive has no object members: ${archive_abs}"

for member in "${members[@]}"; do
  build_info="$(vtool -show-build "${member}")"
  printf '%s\n' "${build_info}"
  if ! grep -Eq "^[[:space:]]+platform[[:space:]]+${expected_platform}$" <<<"${build_info}"; then
    actual_platform="$(sed -nE 's/^[[:space:]]*platform[[:space:]]+([^[:space:]]+).*/\1/p' <<<"${build_info}" | head -n 1)"
    fail "$(basename "${member}") has platform '${actual_platform:-unknown}', expected '${expected_platform}'. Rebuild every iOS core member with the matching iPhoneOS/iPhoneSimulator SDK; do not archive host-macOS objects."
  fi
done

log "PASS: all ${#members[@]} members carry ${expected_platform} metadata"
