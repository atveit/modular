#!/usr/bin/env bash
# Compile-only SwiftUI/Clang-module adoption probe for the iOS Simulator.
# This intentionally stops before application linking and signing.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
target_triple="${MOJO_IOS_SWIFT_TRIPLE:-arm64-apple-ios17.0-simulator}"
sdk_name="iphonesimulator"
output_root="${MOJO_IOS_SWIFT_OUT:-/tmp/mojo-ios-swiftui-probe}"

log() {
  printf '[mojo-ios-swiftui] %s\n' "$*"
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
mkdir -p "${output_root}/module-cache"

log "compiler: ${swift_bin}"
log "target: ${target_triple}"
log "SDK: ${sdk_path}"
"${swift_bin}" \
  -parse-as-library \
  -target "${target_triple}" \
  -sdk "${sdk_path}" \
  -module-cache-path "${output_root}/module-cache" \
  -Xcc "-fmodule-map-file=${script_dir}/MojoIOSSmoke.modulemap" \
  -emit-module \
  -emit-module-path "${output_root}/MojoIOSSmokeApp.swiftmodule" \
  -emit-object \
  "${script_dir}/MojoIOSSmokeApp.swift" \
  -o "${output_root}/MojoIOSSmokeApp.o"

file "${output_root}/MojoIOSSmokeApp.o" "${output_root}/MojoIOSSmokeApp.swiftmodule"
log "PASS: SwiftUI source and C module import compiled for the Simulator"
