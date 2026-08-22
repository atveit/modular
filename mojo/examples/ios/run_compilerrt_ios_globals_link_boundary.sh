#!/usr/bin/env bash
# Demonstrate the four-source CompilerRT seed's global-table link boundary.
# This expected-failure Simulator diagnostic neither links an app nor runs one.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_COMPILERRT_GLOBALS_BOUNDARY_OUT:-${repo_root}/bazel-out/ios-compilerrt-globals-boundary}"
bootstrap_root="${output_root}/bootstrap"
archive_path="${bootstrap_root}/arm64-apple-ios17.0-simulator/libKGENCompilerRTIOSBootstrap.a"
consumer_object="${output_root}/globals_boundary_main.o"
link_log="${output_root}/globals_boundary_link.log"
executable_path="${output_root}/globals_boundary"

log() { printf '[ios-compilerrt-globals-boundary] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
mkdir -p "${output_root}"

log "building fresh Simulator bootstrap archive"
MOJO_IOS_COMPILERRT_BOOTSTRAP_OUT="${bootstrap_root}" \
MOJO_IOS_COMPILERRT_BOOTSTRAP_PLATFORM=simulator \
  "${script_dir}/run_compilerrt_ios_bootstrap_archive_probe.sh"

[[ -f "${archive_path}" ]] || fail "bootstrap archive was not produced: ${archive_path}"
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clang_bin="$(xcrun --sdk iphonesimulator --find clang)"
clangxx_bin="$(xcrun --sdk iphonesimulator --find clang++)"

log "compiling C global-table consumer"
"${clang_bin}" -target arm64-apple-ios17.0-simulator -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  -c "${script_dir}/compilerrt_globals_link_boundary_main.c" -o "${consumer_object}"

log "expecting unresolved GlobalTable support when linking the four-source seed"
if "${clangxx_bin}" -target arm64-apple-ios17.0-simulator -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  "${consumer_object}" "${archive_path}" -o "${executable_path}" >"${link_log}" 2>&1; then
  fail "unexpected global-table link success; update the dependency boundary before claiming it"
fi

cat "${link_log}"
grep -Eq 'GlobalTable.*(getOrCreate|clear)' "${link_log}" || \
  fail "link failed without the expected GlobalTable boundary: ${link_log}"
log "PASS: expected GlobalTable support link boundary observed"
log "No runtime executable was produced or launched; this does not cover AsyncRT."
