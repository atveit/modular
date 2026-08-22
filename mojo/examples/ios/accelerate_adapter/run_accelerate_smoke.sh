#!/usr/bin/env bash
# Direct-C Accelerate coverage for the iOS Simulator. By default this is a
# compile/link-only check; RUN_SIMULATOR=1 adds a signed Simulator launch that
# verifies the vDSP result marker. Neither path uses Mojo or claims ANE use.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
target_triple="${MOJO_IOS_ACCELERATE_TRIPLE:-arm64-apple-ios17.0-simulator}"
target_cpu="${MOJO_IOS_ACCELERATE_CPU:-apple-m1}"
sdk_name="iphonesimulator"
output_root="${MOJO_IOS_ACCELERATE_OUT:-/tmp/mojo-ios-accelerate-probe}"
adapter_object="${output_root}/mojo_ios_accelerate.o"
executable_path="${output_root}/accelerate_consumer"
app_id="com.modular.mojo.ios.accelerate"

log() {
  printf '[mojo-ios-accelerate] %s\n' "$*"
}

command -v "${swift_bin}" >/dev/null 2>&1 || {
  log "ERROR: SWIFT_BIN='${swift_bin}' was not found" >&2
  exit 1
}
command -v xcrun >/dev/null 2>&1 || {
  log "ERROR: xcrun is required" >&2
  exit 1
}

sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
mkdir -p "${output_root}/module-cache"

log "target: ${target_triple} (${target_cpu})"
log "SDK: ${sdk_path}"
log "compiling C Accelerate adapter"
"${clang_bin}" \
  -target "${target_triple}" \
  -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 \
  -I"${script_dir}" \
  -c "${script_dir}/mojo_ios_accelerate.c" \
  -o "${adapter_object}"

log "linking Swift consumer and Accelerate.framework"
SDKROOT="${sdk_path}" "${swift_bin}" \
  -parse-as-library \
  -target "${target_triple}" \
  -sdk "${sdk_path}" \
  -module-cache-path "${output_root}/module-cache" \
  -Xcc "-fmodule-map-file=${script_dir}/MojoIOSAccelerate.modulemap" \
  "${script_dir}/AccelerateConsumer.swift" \
  "${adapter_object}" \
  -framework Accelerate \
  -o "${executable_path}"

file "${adapter_object}" "${executable_path}"
nm -gU "${adapter_object}" | grep -E '(_?mojo_accelerate_vector_add)$'
nm -gU "${executable_path}" | grep -E '(_?mojo_accelerate_vector_add)$'
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${executable_path}" | sed -n '1,100p'
fi
otool -L "${executable_path}" | grep -F 'Accelerate.framework/Accelerate'
log "PASS: direct-C Accelerate adapter and Swift consumer linked for iOS Simulator"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "compile/link-only evidence (set RUN_SIMULATOR=1 for the vDSP Simulator runtime check)"
  exit 0
fi

if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  log "SKIP: CoreSimulator is unavailable"
  exit 0
fi

device_udid="${SIMULATOR_UDID:-}"
if [[ -z "${device_udid}" ]]; then
  device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
fi
if [[ -z "${device_udid}" ]]; then
  log "SKIP: no available iPhone Simulator device"
  exit 0
fi

app_root="$(mktemp -d "${output_root}/accelerate-app.XXXXXX")"
app_path="${app_root}/MojoIOSAccelerate.app"
launch_log="${output_root}/accelerate-launch.log"
log "packaging and ad-hoc signing Simulator app"
mkdir -p "${app_path}"
cp "${script_dir}/../Info.plist" "${app_path}/Info.plist"
cp "${executable_path}" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
codesign --verify --deep --strict "${app_path}"

log "booting ${device_udid}"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
log "installing ${app_path}"
xcrun simctl install "${device_udid}" "${app_path}"
log "launching vDSP runtime check"
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${launch_log}"
grep -qx 'MOJO_ACCELERATE_VDSP_PASS' "${launch_log}" || {
  log "ERROR: vDSP runtime marker was not observed" >&2
  exit 1
}
log "PASS: vDSP computation completed on iOS Simulator"
log "This is Accelerate/vDSP runtime evidence only; it is not Mojo or ANE evidence."
