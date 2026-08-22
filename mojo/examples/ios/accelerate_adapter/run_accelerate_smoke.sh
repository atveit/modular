#!/usr/bin/env bash
# Compile/link-only direct-C Accelerate coverage for the iOS Simulator.
# This deliberately does not require rules_apple/rules_swift or Mojo runtime
# support; it validates a stable C adapter and Swift/Clang consumer boundary.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
target_triple="${MOJO_IOS_ACCELERATE_TRIPLE:-arm64-apple-ios17.0-simulator}"
target_cpu="${MOJO_IOS_ACCELERATE_CPU:-apple-m1}"
sdk_name="iphonesimulator"
output_root="${MOJO_IOS_ACCELERATE_OUT:-/tmp/mojo-ios-accelerate-probe}"
adapter_object="${output_root}/mojo_ios_accelerate.o"
executable_path="${output_root}/accelerate_consumer"

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
