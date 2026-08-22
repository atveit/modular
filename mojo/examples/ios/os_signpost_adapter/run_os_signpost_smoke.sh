#!/usr/bin/env bash
# Direct-C public os/signpost fixture. This is artifact-only: it compiles and
# links iPhone OS and iPhone Simulator slices, without a Mojo runtime or app.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
output_root="${MOJO_IOS_OS_SIGNPOST_OUT:-/tmp/mojo-ios-os-signpost-probe}"
minimum_os="${MOJO_IOS_OS_SIGNPOST_MIN_OS:-17.0}"

log() { printf '[mojo-ios-os-signpost] %s\n' "$*"; }
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
  local adapter_object="${target_output}/mojo_ios_os_signpost.o"
  local executable_path="${target_output}/os_signpost_consumer"

  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
  mkdir -p "${target_output}/module-cache"

  log "target: ${target_triple} (${sdk_name})"
  log 'compiling C os/signpost adapter'
  "${clang_bin}" \
    -target "${target_triple}" \
    -isysroot "${sdk_path}" \
    "${minimum_os_flag}" \
    -I"${script_dir}" \
    -c "${script_dir}/mojo_ios_os_signpost.c" \
    -o "${adapter_object}"

  log 'linking Swift consumer with the iOS SDK system library'
  SDKROOT="${sdk_path}" "${swift_bin}" \
    -parse-as-library \
    -target "${target_triple}" \
    -sdk "${sdk_path}" \
    -module-cache-path "${target_output}/module-cache" \
    -Xcc "-fmodule-map-file=${script_dir}/MojoIOSOSSignpost.modulemap" \
    "${script_dir}/OSSignpostConsumer.swift" \
    "${adapter_object}" \
    -o "${executable_path}"

  file "${adapter_object}" "${executable_path}"
  nm -gU "${adapter_object}" | grep -E '(_?mojo_os_signpost_emit)$'
  nm -gU "${executable_path}" | grep -E '(_?mojo_os_signpost_emit)$'
  nm -u "${adapter_object}" | grep -E 'os_signpost.*emit|os_log_type_enabled'
  otool -L "${executable_path}" | grep -F '/usr/lib/libSystem.B.dylib'
  if command -v vtool >/dev/null 2>&1; then
    vtool -show-build "${executable_path}" | grep -q "platform ${expected_platform}" || fail "wrong platform for ${sdk_name}"
  fi
  log "PASS: os/signpost adapter and Swift consumer linked for ${sdk_name}"
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

log 'PASS: compile/link-only evidence for both iOS slices.'
log 'No Simulator launch, signpost collection, Mojo runtime, or physical-device claim is made.'
