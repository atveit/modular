#!/usr/bin/env bash
# Build and run the N5 serial-core C-ABI stress gate. The final image is dead
# stripped and contains exactly one target-correct CompilerRT core archive.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_CORE_ABI_STRESS_OUT:-${repo_root}/bazel-out/ios-core-abi-stress}"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
bazel_wrapper="${repo_root}/bazelw"

log() { printf '[ios-core-abi-stress] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
mkdir -p "${output_root}"

"${bazel_wrapper}" build --config=build-mojo --jobs=16 \
  //KGEN:mojo \
  //mojo/examples/ios:compilerrt_ios_core_simulator_archive \
  //mojo/examples/ios:compilerrt_ios_core_device_archive
[[ -x "${mojo_bin}" ]] || fail "repository Mojo compiler is unavailable"

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clang_bin="$(xcrun --sdk iphonesimulator --find clang)"
target_triple=arm64-apple-ios17.0-simulator
core_archive="${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core_simulator_archive.a"
mojo_smoke_object="${output_root}/mojo_ios_smoke.o"
mojo_abi_object="${output_root}/mojo_ios_core_abi_probe.o"
mojo_string_object="${output_root}/mojo_ios_runtime_probe.o"
consumer_object="${output_root}/compilerrt_core_abi_stress_main.o"
executable_path="${output_root}/compilerrt_core_abi_stress"

for source_spec in \
  "${script_dir}/mojo_ios_smoke.mojo:${mojo_smoke_object}" \
  "${script_dir}/mojo_ios_core_abi_probe.mojo:${mojo_abi_object}" \
  "${script_dir}/mojo_ios_runtime_probe.mojo:${mojo_string_object}"; do
  source_path="${source_spec%%:*}"
  object_path="${source_spec##*:}"
  MOJO_CRASHPAD=0 "${mojo_bin}" build \
    --target-triple "${target_triple}" --target-cpu apple-m1 \
    -I "${stdlib_path}" --emit object "${source_path}" -o "${object_path}"
  vtool -show-build "${object_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong Mojo object platform"
  ! nm -u "${object_path}" | grep -q 'KGEN_CompilerRT_AsyncRT_' || fail "serial ABI object acquired AsyncRT"
done

"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 -O2 \
  -I "${script_dir}" -c "${script_dir}/compilerrt_core_abi_stress_main.c" \
  -o "${consumer_object}"

"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 -O2 -Wl,-dead_strip \
  "${consumer_object}" "${mojo_smoke_object}" "${mojo_abi_object}" \
  "${mojo_string_object}" "${core_archive}" -lc++ -o "${executable_path}"

vtool -show-build "${executable_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong executable platform"
! nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_' || fail "unresolved CompilerRT symbol"
nm -gU "${executable_path}" | grep -q '_mojo_ios_handle_create' || fail "used handle export was stripped"
! nm -gU "${executable_path}" | grep -q '_mojo_ios_dead_strip_sentinel' || fail "unused export survived dead stripping"

device_out="${output_root}/device"
mkdir -p "${device_out}"
device_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
device_clang_bin="$(xcrun --sdk iphoneos --find clang)"
device_core_archive="${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core_device_archive.a"
device_objects=()
for source_name in mojo_ios_smoke mojo_ios_core_abi_probe mojo_ios_runtime_probe; do
  device_object="${device_out}/${source_name}.o"
  MOJO_CRASHPAD=0 "${mojo_bin}" build \
    --target-triple arm64-apple-ios17.0 --target-cpu apple-a7 \
    -I "${stdlib_path}" --emit object "${script_dir}/${source_name}.mojo" \
    -o "${device_object}"
  vtool -show-build "${device_object}" | grep -q 'platform IOS' || fail "wrong device Mojo object platform"
  ! nm -u "${device_object}" | grep -q 'KGEN_CompilerRT_AsyncRT_' || fail "device serial ABI object acquired AsyncRT"
  device_objects+=("${device_object}")
done
device_consumer_object="${device_out}/compilerrt_core_abi_stress_main.o"
device_executable="${device_out}/compilerrt_core_abi_stress"
"${device_clang_bin}" -target arm64-apple-ios17.0 -isysroot "${device_sdk_path}" \
  -miphoneos-version-min=17.0 -arch arm64 -O2 -I "${script_dir}" \
  -c "${script_dir}/compilerrt_core_abi_stress_main.c" \
  -o "${device_consumer_object}"
"${device_clang_bin}" -target arm64-apple-ios17.0 -isysroot "${device_sdk_path}" \
  -miphoneos-version-min=17.0 -arch arm64 -O2 -Wl,-dead_strip \
  "${device_consumer_object}" "${device_objects[@]}" "${device_core_archive}" \
  -lc++ -o "${device_executable}"
vtool -show-build "${device_executable}" | grep -q 'platform IOS' || fail "wrong device executable platform"
! nm -u "${device_executable}" | grep -q 'KGEN_CompilerRT_' || fail "unresolved device CompilerRT symbol"
! nm -gU "${device_executable}" | grep -q '_mojo_ios_dead_strip_sentinel' || fail "unused device export survived dead stripping"
log "PASS: device ABI stress artifact links with IOS iOS 17 metadata"

duplicate_log="${output_root}/duplicate-runtime-link.log"
duplicate_archive="${output_root}/libcompilerrt_ios_core_duplicate.a"
rm -f "${duplicate_archive}"
cp "${core_archive}" "${duplicate_archive}"
if "${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  "${consumer_object}" "${mojo_smoke_object}" "${mojo_abi_object}" \
  "${mojo_string_object}" -Wl,-force_load,"${core_archive}" \
  -Wl,-force_load,"${duplicate_archive}" -lc++ \
  -o "${output_root}/duplicate-runtime-must-not-link" \
  >"${duplicate_log}" 2>&1; then
  fail "force-loading the runtime twice unexpectedly linked"
fi
grep -q 'duplicate symbol' "${duplicate_log}" || fail "duplicate-runtime failure was not explicit"
log "PASS: duplicate runtime force-load is rejected by the linker"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: dead-stripped Simulator artifact; set RUN_SIMULATOR=1 to execute stress"
  exit 0
fi

device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
[[ -n "${device_udid}" ]] || { log "SKIP: no available iPhone Simulator"; exit 0; }
app_id=com.modular.mojo.ios.core-abi-stress
app_path="${output_root}/core_abi_stress.app"
rm -rf "${app_path}"
mkdir -p "${app_path}"
cp "${script_dir}/Info.plist" "${app_path}/Info.plist"
cp "${executable_path}" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
xcrun simctl install "${device_udid}" "${app_path}"
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${output_root}/launch.log"
grep -qx 'MOJO_COMPILERRT_CORE_ABI_STRESS_PASS' "${output_root}/launch.log" || fail "missing stress marker"
log "PASS: 10,000 caller-buffer, opaque-handle, Error-status, allocation/String, and scalar calls completed with clean process exit"
log "No sanitizer-backed leak/race claim, AsyncRT, threading, or physical-device claim."
