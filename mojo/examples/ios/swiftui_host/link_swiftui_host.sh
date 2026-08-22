#!/usr/bin/env bash
# Link a source-only SwiftUI host with the runtime-free Mojo C ABI archive.
# This is a discovery probe, not a replacement for an ios_application rule.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
target_triple="${MOJO_IOS_SWIFT_TRIPLE:-arm64-apple-ios17.0-simulator}"
sdk_name="iphonesimulator"
archive_path="${MOJO_IOS_ARCHIVE:-${repo_root}/bazel-out/ios-mojo-smoke/libmojo_ios_smoke.a}"
output_root="${MOJO_IOS_SWIFT_LINK_OUT:-/tmp/mojo-ios-swiftui-link-probe}"
executable_path="${output_root}/MojoIOSSmokeApp"
app_path="${output_root}/MojoIOSSmoke.app"

log() {
  printf '[mojo-ios-swiftui-link] %s\n' "$*"
}

command -v "${swift_bin}" >/dev/null 2>&1 || {
  log "ERROR: SWIFT_BIN='${swift_bin}' was not found" >&2
  exit 1
}
command -v xcrun >/dev/null 2>&1 || {
  log "ERROR: xcrun is required" >&2
  exit 1
}
[[ -f "${archive_path}" ]] || {
  log "ERROR: archive not found: ${archive_path}"
  log "Run ../run_simulator_smoke.sh first, or set MOJO_IOS_ARCHIVE."
  exit 1
}

sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
mkdir -p "${output_root}/module-cache" "${app_path}"

log "compiler: ${swift_bin}"
log "target: ${target_triple}"
log "SDK: ${sdk_path}"
log "archive: ${archive_path}"
# Swift's linker can retain the host MacOSX sysroot when only `-sdk` is
# passed. Set SDKROOT as well so the link action and its diagnostics use the
# same iPhone Simulator SDK; vtool below still verifies the final image.
SDKROOT="${sdk_path}" "${swift_bin}" \
  -parse-as-library \
  -target "${target_triple}" \
  -sdk "${sdk_path}" \
  -module-cache-path "${output_root}/module-cache" \
  -Xcc "-fmodule-map-file=${script_dir}/MojoIOSSmoke.modulemap" \
  "${script_dir}/MojoIOSSmokeApp.swift" \
  "${archive_path}" \
  -o "${executable_path}"

cp "${executable_path}" "${app_path}/mojo_ios_smoke"
cp "${script_dir}/../Info.plist" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
codesign --verify --deep --strict "${app_path}"

file "${executable_path}" "${app_path}/mojo_ios_smoke"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${executable_path}" | sed -n '1,100p'
fi
nm -gU "${executable_path}" | grep -E '(_?mojo_add|_?mojo_hello_utf8)$'
log "PASS: SwiftUI host linked with the Mojo archive and was packaged as ${app_path}"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "set RUN_SIMULATOR=1 to install and launch the SwiftUI app"
  exit 0
fi

if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  log "SKIP: CoreSimulator is unavailable in this environment"
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

app_id="com.modular.mojo.ios.smoke"
log "booting ${device_udid}"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
log "installing ${app_path} on ${device_udid}"
xcrun simctl install "${device_udid}" "${app_path}"
log "launching ${app_id}"
xcrun simctl launch "${device_udid}" "${app_id}"
log "PASS: SwiftUI Simulator launch requested"
