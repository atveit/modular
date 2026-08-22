#!/usr/bin/env bash
# Direct-C CoreGraphics fixture for iPhone OS and iPhone Simulator.
# Default coverage is compile/link-only. RUN_SIMULATOR=1 runs only the
# Simulator slice and validates the scalar/POD adapter's deterministic marker.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
output_root="${MOJO_IOS_COREGRAPHICS_OUT:-/tmp/mojo-ios-coregraphics-probe}"
minimum_os="${MOJO_IOS_COREGRAPHICS_MIN_OS:-17.0}"
app_id="com.modular.mojo.ios.coregraphics"

log() { printf '[mojo-ios-coregraphics] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${swift_bin}" >/dev/null 2>&1 || fail "SWIFT_BIN='${swift_bin}' was not found"
command -v xcrun >/dev/null 2>&1 || fail 'xcrun is required'
mkdir -p "${output_root}"

build_target() {
  local sdk_name="$1"
  local target_triple="$2"
  local minimum_os_flag="$3"
  local expected_platform="$4"
  local target_output="${output_root}/${sdk_name}"
  local sdk_path
  local clang_bin
  local adapter_object="${target_output}/mojo_ios_coregraphics.o"
  local executable_path="${target_output}/coregraphics_consumer"

  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
  mkdir -p "${target_output}/module-cache"

  log "target: ${target_triple} (${sdk_name})"
  log "SDK: ${sdk_path}"
  log "compiling C CoreGraphics adapter"
  "${clang_bin}" \
    -target "${target_triple}" \
    -isysroot "${sdk_path}" \
    "${minimum_os_flag}" \
    -I"${script_dir}" \
    -c "${script_dir}/mojo_ios_coregraphics.c" \
    -o "${adapter_object}"

  log "linking Swift consumer and CoreGraphics.framework"
  SDKROOT="${sdk_path}" "${swift_bin}" \
    -parse-as-library \
    -target "${target_triple}" \
    -sdk "${sdk_path}" \
    -module-cache-path "${target_output}/module-cache" \
    -Xcc "-fmodule-map-file=${script_dir}/MojoIOSCoreGraphics.modulemap" \
    "${script_dir}/CoreGraphicsConsumer.swift" \
    "${adapter_object}" \
    -framework CoreGraphics \
    -o "${executable_path}"

  file "${adapter_object}" "${executable_path}"
  nm -gU "${adapter_object}" | grep -E '(_?mojo_coregraphics_rect_area)$'
  nm -gU "${executable_path}" | grep -E '(_?mojo_coregraphics_rect_area)$'
  nm -u "${adapter_object}" | grep -F '_CGColorSpaceCreateDeviceRGB'
  nm -u "${executable_path}" | grep -F '_CGColorSpaceCreateDeviceRGB'
  if command -v vtool >/dev/null 2>&1; then
    vtool -show-build "${executable_path}" | sed -n '1,100p'
    vtool -show-build "${executable_path}" | grep -q "platform ${expected_platform}" || fail "wrong platform for ${sdk_name}"
  fi
  otool -L "${executable_path}" | grep -F 'CoreGraphics.framework/CoreGraphics'
  log "PASS: CoreGraphics adapter and Swift consumer linked for ${sdk_name}"
}

build_target \
  iphonesimulator \
  "arm64-apple-ios${minimum_os}-simulator" \
  "-mios-simulator-version-min=${minimum_os}" \
  IOSSIMULATOR
build_target \
  iphoneos \
  "arm64-apple-ios${minimum_os}" \
  "-miphoneos-version-min=${minimum_os}" \
  IOS

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log 'compile/link-only evidence for both iOS slices (set RUN_SIMULATOR=1 for CoreGraphics Simulator runtime evidence)'
  exit 0
fi

if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  log 'SKIP: CoreSimulator is unavailable'
  exit 0
fi

device_udid="${SIMULATOR_UDID:-}"
if [[ -z "${device_udid}" ]]; then
  device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
fi
if [[ -z "${device_udid}" ]]; then
  log 'SKIP: no available iPhone Simulator device'
  exit 0
fi

app_root="$(mktemp -d "${output_root}/coregraphics-app.XXXXXX")"
app_path="${app_root}/MojoIOSCoreGraphics.app"
launch_log="${output_root}/coregraphics-launch.log"
log 'packaging and ad-hoc signing Simulator app'
mkdir -p "${app_path}"
cp "${script_dir}/../Info.plist" "${app_path}/Info.plist"
cp "${output_root}/iphonesimulator/coregraphics_consumer" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
codesign --verify --deep --strict "${app_path}"

log "booting ${device_udid}"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
log "installing ${app_path}"
xcrun simctl install "${device_udid}" "${app_path}"
log 'launching CoreGraphics runtime check'
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${launch_log}"
grep -qx 'MOJO_COREGRAPHICS_RECT_PASS' "${launch_log}" || fail 'CoreGraphics runtime marker was not observed'
log 'PASS: CoreGraphics scalar/POD adapter completed on iOS Simulator'
log 'This is CoreGraphics runtime evidence only; it is not Mojo runtime or physical-device evidence.'
