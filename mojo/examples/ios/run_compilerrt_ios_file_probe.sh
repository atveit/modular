#!/usr/bin/env bash
# Compile/link a real Mojo stdlib file roundtrip against the bounded iOS core
# seed for Simulator and device. Simulator execution is explicit opt-in.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_FILE_PROBE_OUT:-${repo_root}/bazel-out/ios-file-probe}"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
bazel_wrapper="${repo_root}/bazelw"

log() { printf '[ios-file-probe] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[[ -x "${bazel_wrapper}" ]] || fail "bazelw is required"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is unavailable: ${stdlib_path}"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
mkdir -p "${output_root}/simulator" "${output_root}/device"

log "building the repository compiler and both SDK-native core-seed archives"
"${bazel_wrapper}" build --config=build-mojo --jobs=16 \
  //KGEN:mojo \
  //mojo/examples/ios:compilerrt_ios_core_simulator_archive \
  //mojo/examples/ios:compilerrt_ios_core_device_archive
[[ -x "${mojo_bin}" ]] || fail "MOJO_BIN is unavailable: ${mojo_bin}"

build_platform() {
  local platform="$1"
  local sdk_name target_triple target_cpu minimum_os_flag expected_platform archive_path
  if [[ "${platform}" == simulator ]]; then
    sdk_name=iphonesimulator
    target_triple=arm64-apple-ios17.0-simulator
    target_cpu=apple-m1
    minimum_os_flag=-mios-simulator-version-min=17.0
    expected_platform=IOSSIMULATOR
    archive_path="${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core_simulator_archive.a"
  else
    sdk_name=iphoneos
    target_triple=arm64-apple-ios17.0
    target_cpu=apple-a7
    minimum_os_flag=-miphoneos-version-min=17.0
    expected_platform=IOS
    archive_path="${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core_device_archive.a"
  fi

  local platform_out="${output_root}/${platform}"
  local sdk_path clang_bin mojo_object consumer_object executable_path
  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
  mojo_object="${platform_out}/mojo_ios_file_probe.o"
  consumer_object="${platform_out}/compilerrt_file_probe_main.o"
  executable_path="${platform_out}/compilerrt_file_probe"

  log "emitting the ${platform} Mojo file object"
  MOJO_CRASHPAD=0 "${mojo_bin}" build \
    --target-triple "${target_triple}" --target-cpu "${target_cpu}" \
    -I "${stdlib_path}" --emit object \
    "${script_dir}/mojo_ios_file_probe.mojo" -o "${mojo_object}"
  vtool -show-build "${mojo_object}" | grep -q "platform ${expected_platform}" || fail "wrong Mojo object platform"
  nm -u "${mojo_object}" | grep -qx _KGEN_CompilerRT_fprintf || fail "formatted-print ABI dependency missing"
  nm -u "${mojo_object}" | grep -qx _open || fail "Darwin open dependency missing"
  nm -u "${mojo_object}" | grep -qx _read || fail "Darwin read dependency missing"
  nm -u "${mojo_object}" | grep -qx _write || fail "Darwin write dependency missing"
  nm -u "${mojo_object}" | grep -qx _getenv || fail "Darwin getenv dependency missing"
  nm -u "${mojo_object}" | grep -qx _setenv || fail "Darwin setenv dependency missing"
  nm -u "${mojo_object}" | grep -qx _unsetenv || fail "Darwin unsetenv dependency missing"

  "${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
    "${minimum_os_flag}" -arch arm64 \
    -c "${script_dir}/compilerrt_file_probe_main.c" -o "${consumer_object}"
  "${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
    "${minimum_os_flag}" -arch arm64 \
    "${consumer_object}" "${mojo_object}" "${archive_path}" -lc++ \
    -o "${executable_path}"
  ! nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_' || fail "residual CompilerRT symbols"
  vtool -show-build "${executable_path}" | grep -q "platform ${expected_platform}" || fail "wrong executable platform"
  log "PASS: ${platform} file probe compiled and linked"
}

build_platform simulator
build_platform device

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: dual-platform artifact evidence only (set RUN_SIMULATOR=1 to execute)"
  exit 0
fi

xcrun simctl list runtimes >/dev/null 2>&1 || { log "SKIP: CoreSimulator unavailable"; exit 0; }
device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
[[ -n "${device_udid}" ]] || { log "SKIP: no available iPhone Simulator"; exit 0; }
app_id="com.modular.mojo.ios.file-probe"
app_path="${output_root}/simulator/compilerrt_file_probe.app"
rm -rf "${app_path}"
mkdir -p "${app_path}"
cp "${script_dir}/Info.plist" "${app_path}/Info.plist"
cp "${output_root}/simulator/compilerrt_file_probe" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
xcrun simctl install "${device_udid}" "${app_path}"
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${output_root}/simulator/launch.log"
grep -qx 'MOJO_COMPILERRT_FILE_ROUNDTRIP_PASS' "${output_root}/simulator/launch.log" || fail "missing file roundtrip marker"
log "PASS: Mojo roundtripped an environment value and an app-sandbox temporary file in Simulator"
log "No initialize_runtime, AsyncRT, threading, arbitrary filesystem, or physical-device execution claim."
