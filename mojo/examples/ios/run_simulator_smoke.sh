#!/usr/bin/env bash
# Build and statically link the runtime-free Mojo iOS C ABI fixture.
#
# This is a discovery harness for Phase 1. It intentionally does not pretend
# to be an ios_application rule: rules_apple/rules_swift are not registered in
# this repository yet, and the full Mojo runtime cannot currently be linked for
# an iOS target. By default this emits a genuine arm64 Simulator Mach-O image;
# set `MOJO_IOS_TRIPLE=arm64-apple-ios17.0` to run the device-link variant,
# which stops before signing or installation.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-mojo}"
mojo_stdlib_path="${MOJO_STDLIB_PATH:-}"
target_triple="${MOJO_IOS_TRIPLE:-${MOJO_IOS_SIMULATOR_TRIPLE:-arm64-apple-ios17.0-simulator}}"
target_cpu="${MOJO_IOS_CPU:-}"

case "${target_triple}" in
  *-simulator)
    platform="simulator"
    sdk_name="iphonesimulator"
    minimum_os_flag="-mios-simulator-version-min=17.0"
    expected_platform="IOSSIMULATOR"
    default_cpu="apple-m1"
    if [[ -z "${target_cpu}" ]]; then
      target_cpu="${MOJO_IOS_SIMULATOR_CPU:-${default_cpu}}"
    fi
    default_output_root="${repo_root}/bazel-out/ios-mojo-smoke"
    executable_basename="mojo_ios_smoke_simulator"
    ;;
  *-ios*)
    platform="device"
    sdk_name="iphoneos"
    minimum_os_flag="-miphoneos-version-min=17.0"
    expected_platform="IOS"
    default_cpu="apple-a7"
    if [[ -z "${target_cpu}" ]]; then
      target_cpu="${default_cpu}"
    fi
    default_output_root="${repo_root}/bazel-out/ios-mojo-smoke-device"
    executable_basename="mojo_ios_smoke_device"
    ;;
  *)
    printf '[ios-mojo-smoke] ERROR: MOJO_IOS_TRIPLE must be an iOS device or Simulator triple: %s\n' "${target_triple}" >&2
    exit 1
    ;;
esac

output_root="${MOJO_IOS_SMOKE_OUT:-${default_output_root}}"

log() {
  printf '[ios-mojo-smoke] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${mojo_bin}" >/dev/null 2>&1 || fail "MOJO_BIN='${mojo_bin}' was not found"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
command -v clang >/dev/null 2>&1 || fail "clang is required"
command -v ar >/dev/null 2>&1 || fail "ar is required"

sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
mkdir -p "${output_root}"
object_path="${output_root}/mojo_ios_smoke.o"
archive_path="${output_root}/libmojo_ios_smoke.a"
executable_path="${output_root}/${executable_basename}"
app_path="${output_root}/mojo_ios_smoke.app"

log "compiler: ${mojo_bin}"
log "target: ${target_triple} (${target_cpu})"
log "SDK: ${sdk_path}"
if [[ -n "${mojo_stdlib_path}" ]]; then
  log "stdlib: ${mojo_stdlib_path}"
fi
log "emitting target object"
mojo_build_args=(
  build
  --target-triple "${target_triple}"
  --target-cpu "${target_cpu}"
  --emit object
  "${script_dir}/mojo_ios_smoke.mojo"
  -o "${object_path}"
)
if [[ -n "${mojo_stdlib_path}" ]]; then
  mojo_build_args=("${mojo_build_args[@]:0:1}" -I "${mojo_stdlib_path}" "${mojo_build_args[@]:1}")
fi
"${mojo_bin}" "${mojo_build_args[@]}"

log "archiving object"
rm -f "${archive_path}"
ar -rcs "${archive_path}" "${object_path}"

log "compiling C ABI consumer"
"$(xcrun --sdk "${sdk_name}" --find clang)" \
  -isysroot "${sdk_path}" \
  "${minimum_os_flag}" \
  -arch arm64 \
  -I"${script_dir}" \
  -c "${script_dir}/smoke_main.c" \
  -o "${output_root}/smoke_main.o"

log "linking ${platform} executable"
clang_args=(
  -isysroot "${sdk_path}"
  "${minimum_os_flag}"
  -arch arm64
)
"$(xcrun --sdk "${sdk_name}" --find clang)" \
  "${clang_args[@]}" \
  "${output_root}/smoke_main.o" \
  "${archive_path}" \
  -o "${executable_path}"

if [[ "${platform}" == "simulator" ]]; then
  log "ad-hoc signing"
  codesign --force --sign - "${executable_path}" >/dev/null

  log "packaging minimal Simulator app bundle"
  rm -rf "${app_path}"
  mkdir -p "${app_path}"
  cp "${script_dir}/Info.plist" "${app_path}/Info.plist"
  cp "${executable_path}" "${app_path}/mojo_ios_smoke"
  codesign --force --sign - "${app_path}" >/dev/null
fi

log "verifying Mach-O architecture, symbols, and platform metadata"
artifacts=("${object_path}" "${archive_path}" "${executable_path}")
if [[ "${platform}" == "simulator" ]]; then
  artifacts+=("${app_path}/mojo_ios_smoke")
fi
file "${artifacts[@]}"
nm -gU "${object_path}" | grep -E '(_?mojo_add|_?mojo_hello_utf8)$'
ar -t "${archive_path}" | grep -q 'mojo_ios_smoke.o'
if command -v vtool >/dev/null 2>&1; then
  for artifact in "${object_path}" "${executable_path}"; do
    build_metadata="$(vtool -show-build "${artifact}")"
    printf '%s\n' "${build_metadata}" | sed -n '1,100p'
    printf '%s\n' "${build_metadata}" | grep -q "platform ${expected_platform}"
  done
else
  log "vtool is unavailable; use xcrun vtool -show-build manually"
fi

if [[ "${platform}" != "simulator" ]]; then
  log "PASS: device object/archive/link smoke test complete (signing/install intentionally skipped)"
  exit 0
fi

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: Simulator object/archive/link smoke test complete (set RUN_SIMULATOR=1 to install and launch)"
  exit 0
fi

log "checking CoreSimulator availability"
if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  log "SKIP: CoreSimulator is unavailable in this environment"
  exit 0
fi

device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
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
log "PASS: Simulator launch requested"
