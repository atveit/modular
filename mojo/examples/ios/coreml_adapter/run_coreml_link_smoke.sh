#!/usr/bin/env bash
# Artifact-only Core ML framework coverage for iPhone OS and Simulator.
# It compiles an Objective-C C-ABI adapter and links a Swift/Clang consumer.
# It neither bundles a model nor executes Core ML code.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
output_root="${MOJO_IOS_COREML_OUT:-/tmp/mojo-ios-coreml-link-probe}"
minimum_os="${MOJO_IOS_COREML_MIN_OS:-17.0}"

log() {
  printf '[mojo-ios-coreml] %s\n' "$*"
}

command -v "${swift_bin}" >/dev/null 2>&1 || {
  log "ERROR: SWIFT_BIN='${swift_bin}' was not found" >&2
  exit 1
}
command -v xcrun >/dev/null 2>&1 || {
  log "ERROR: xcrun is required" >&2
  exit 1
}

build_target() {
  local sdk_name="$1"
  local target_triple="$2"
  local minimum_os_flag="$3"
  local target_output="${output_root}/${sdk_name}"
  local sdk_path
  local clang_bin
  local adapter_object="${target_output}/mojo_ios_coreml.o"
  local executable_path="${target_output}/coreml_link_consumer"

  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
  mkdir -p "${target_output}/module-cache"

  log "target: ${target_triple} (${sdk_name})"
  log "SDK: ${sdk_path}"
  log "compiling Objective-C Core ML C-ABI adapter"
  "${clang_bin}" \
    -target "${target_triple}" \
    -isysroot "${sdk_path}" \
    "${minimum_os_flag}" \
    -fobjc-arc \
    -I"${script_dir}" \
    -c "${script_dir}/mojo_ios_coreml.m" \
    -o "${adapter_object}"

  log "linking Swift consumer and CoreML.framework"
  SDKROOT="${sdk_path}" "${swift_bin}" \
    -parse-as-library \
    -target "${target_triple}" \
    -sdk "${sdk_path}" \
    -module-cache-path "${target_output}/module-cache" \
    -Xcc "-fmodule-map-file=${script_dir}/MojoIOSCoreML.modulemap" \
    "${script_dir}/CoreMLLinkConsumer.swift" \
    "${adapter_object}" \
    -framework CoreML \
    -o "${executable_path}"

  file "${adapter_object}" "${executable_path}"
  nm -gU "${adapter_object}" | grep -E '(_?mojo_coreml_framework_anchor)$'
  nm -gU "${executable_path}" | grep -E '(_?mojo_coreml_framework_anchor)$'
  log "checking public MLModel class reference"
  nm -u "${adapter_object}" | grep -F '_OBJC_CLASS_$_MLModel'
  nm -u "${executable_path}" | grep -F '_OBJC_CLASS_$_MLModel'
  if command -v vtool >/dev/null 2>&1; then
    vtool -show-build "${executable_path}" | sed -n '1,100p'
  fi
  otool -L "${executable_path}" | grep -F 'CoreML.framework/CoreML'
  log "PASS: CoreML.framework linked for ${sdk_name}; no model/runtime claim"
}

build_target \
  iphonesimulator \
  "arm64-apple-ios${minimum_os}-simulator" \
  "-mios-simulator-version-min=${minimum_os}"
build_target \
  iphoneos \
  "arm64-apple-ios${minimum_os}" \
  "-miphoneos-version-min=${minimum_os}"
