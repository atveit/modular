#!/usr/bin/env bash
# Runtime-backed Mojo String probe for the iOS Simulator only.
#
# A successful result requires a supplied static iOS Simulator Mojo runtime and
# an actual simctl launch. Do not infer runtime coverage from object emission or
# a link-only fixture. The pinned Mojo 1.0.0b1 distribution currently has no
# such archive, so the default result is an explicit SKIP.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="$(cd "${script_dir}/.." && pwd)"
mojo_bin="${MOJO_BIN:-mojo}"
target_triple="${MOJO_IOS_RUNTIME_SIMULATOR_TRIPLE:-arm64-apple-ios17.0-simulator}"
target_cpu="${MOJO_IOS_RUNTIME_SIMULATOR_CPU:-apple-m1}"
runtime_archive="${MOJO_IOS_RUNTIME_ARCHIVE:-}"
output_root="${MOJO_IOS_RUNTIME_OUT:-/tmp/mojo-ios-runtime-string-probe}"

log() {
  printf '[mojo-ios-runtime-string] %s\n' "$*"
}

skip() {
  log "SKIP: $*"
  exit 0
}

command -v "${mojo_bin}" >/dev/null 2>&1 || {
  log "ERROR: MOJO_BIN='${mojo_bin}' was not found" >&2
  exit 1
}
command -v xcrun >/dev/null 2>&1 || {
  log "ERROR: xcrun is required" >&2
  exit 1
}

if [[ -z "${runtime_archive}" ]]; then
  skip "MOJO_IOS_RUNTIME_ARCHIVE is unset; the pinned compiler distribution does not provide a discovered static iOS runtime"
fi
if [[ ! -f "${runtime_archive}" ]]; then
  skip "MOJO_IOS_RUNTIME_ARCHIVE does not name a file: ${runtime_archive}"
fi
if ! xcrun lipo -info "${runtime_archive}" 2>&1 | grep -q 'arm64'; then
  skip "MOJO_IOS_RUNTIME_ARCHIVE has no arm64 slice: ${runtime_archive}"
fi
if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  skip "CoreSimulator is unavailable"
fi

device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
if [[ -z "${device_udid}" ]]; then
  skip "no available iPhone Simulator device"
fi

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clang_bin="$(xcrun --sdk iphonesimulator --find clang)"
object_path="${output_root}/mojo_ios_runtime_string.o"
executable_path="${output_root}/mojo_ios_runtime_string_simulator"
app_id="com.modular.mojo.ios.runtime-string"
mkdir -p "${output_root}"
app_root="$(mktemp -d "${output_root}/app.XXXXXX")"
app_path="${app_root}/mojo_ios_runtime_string.app"

log "compiler: ${mojo_bin} ($(${mojo_bin} --version))"
log "target: ${target_triple} (${target_cpu})"
log "runtime archive: ${runtime_archive}"
log "SDK: ${sdk_path}"
log "emitting runtime-using Mojo object"
"${mojo_bin}" build \
  --target-triple "${target_triple}" \
  --target-cpu "${target_cpu}" \
  --emit object \
  "${script_dir}/mojo_ios_runtime_string.mojo" \
  -o "${object_path}"

log "compiling C ABI runtime consumer"
"${clang_bin}" \
  -target "${target_triple}" \
  -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 \
  -I"${script_dir}" \
  -c "${script_dir}/runtime_string_main.c" \
  -o "${output_root}/runtime_string_main.o"

log "linking static Mojo runtime for Simulator"
"${clang_bin}" \
  -target "${target_triple}" \
  -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 \
  "${output_root}/runtime_string_main.o" \
  "${object_path}" \
  "${runtime_archive}" \
  -lc++ \
  -o "${executable_path}"

log "packaging and signing Simulator app"
mkdir -p "${app_path}"
cp "${ios_dir}/Info.plist" "${app_path}/Info.plist"
cp "${executable_path}" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null

file "${object_path}" "${executable_path}"
nm -gU "${object_path}" | grep -E '(_?mojo_runtime_string_byte_count)$'
vtool -show-build "${executable_path}" | grep -q 'platform IOSSIMULATOR'

log "booting ${device_udid}"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
log "installing ${app_path}"
xcrun simctl install "${device_udid}" "${app_path}"
log "launching runtime probe; output marker proves C assertion passed"
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${output_root}/launch.log"
grep -qx 'MOJO_RUNTIME_STRING_PROBE_PASS' "${output_root}/launch.log"
log "PASS: runtime-backed Mojo String probe completed on iOS Simulator"
