#!/usr/bin/env bash
# Link the bounded non-AsyncRT CompilerRT iOS candidates with emitted Mojo
# global and Error probes. This is not a general static-runtime bootstrap.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_CORE_SEED_PROBE_OUT:-${repo_root}/bazel-out/ios-core-seed-probe}"
bazel_wrapper="${repo_root}/bazelw"

log() { printf '[ios-core-seed-probe] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[[ -x "${mojo_bin}" ]] || fail "MOJO_BIN is unavailable: ${mojo_bin}"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is unavailable: ${stdlib_path}"
[[ -x "${bazel_wrapper}" ]] || fail "bazelw is required"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
mkdir -p "${output_root}"

"${bazel_wrapper}" build --config=build-mojo //KGEN:CompilerRTIOSStatic
exec_root="$("${bazel_wrapper}" info --config=build-mojo execution_root)"
bazel_bin="$("${bazel_wrapper}" info --config=build-mojo bazel-bin)"
llvm_source_include="${exec_root}/external/+llvm_configure+llvm-project/llvm/include"
llvm_generated_include="${bazel_bin}/external/+llvm_configure+llvm-project/llvm/include"
[[ -d "${llvm_source_include}" && -d "${llvm_generated_include}" ]] || fail "missing LLVM headers"

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clang_bin="$(xcrun --sdk iphonesimulator --find clang)"
clangxx_bin="$(xcrun --sdk iphonesimulator --find clang++)"
libtool_bin="$(xcrun --sdk iphonesimulator --find libtool)"
target_triple="arm64-apple-ios17.0-simulator"
common_flags=(-target "${target_triple}" -isysroot "${sdk_path}"
  -mios-simulator-version-min=17.0 -arch arm64 -std=c++20
  -DMODULAR_BUILDING_COMPILERRT -I"${repo_root}/Support/include"
  -isystem "${llvm_source_include}" -isystem "${llvm_generated_include}")

sources=(MemoryIOS.cpp Initialize.cpp GlobalsIOS.cpp StackTraceIOS.cpp)
objects=()
for source in "${sources[@]}"; do
  object_path="${output_root}/${source%.cpp}.o"
  "${clangxx_bin}" "${common_flags[@]}" -c "${repo_root}/KGEN/lib/CompilerRT/${source}" -o "${object_path}"
  vtool -show-build "${object_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong platform: ${source}"
  objects+=("${object_path}")
done
archive_path="${output_root}/libKGENCompilerRTIOSCoreSeedCandidate.a"
"${libtool_bin}" -static -o "${archive_path}" "${objects[@]}"

global_object="${output_root}/mojo_ios_global_symbol_probe.o"
error_object="${output_root}/mojo_ios_error_symbol_probe.o"
for probe in global error; do
  source_path="${script_dir}/mojo_ios_${probe}_symbol_probe.mojo"
  object_path="${output_root}/mojo_ios_${probe}_symbol_probe.o"
  log "emitting ${probe} Mojo object"
  MOJO_CRASHPAD=0 "${mojo_bin}" build --target-triple "${target_triple}" \
    --target-cpu apple-m1 -I "${stdlib_path}" --emit object "${source_path}" -o "${object_path}"
  vtool -show-build "${object_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong ${probe} platform"
done
nm -u "${global_object}" | grep -qx _KGEN_CompilerRT_GetOrCreateGlobal || fail "global ABI missing"
nm -u "${error_object}" | grep -qx _KGEN_CompilerRT_GetStackTrace || fail "error ABI missing"

consumer_object="${output_root}/core_seed_probe_main.o"
executable_path="${output_root}/core_seed_probe"
"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  -c "${script_dir}/compilerrt_core_seed_probe_main.c" -o "${consumer_object}"
"${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  "${consumer_object}" "${global_object}" "${error_object}" "${archive_path}" -o "${executable_path}"
nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_' && fail "residual CompilerRT symbol"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: composite seed compile/link evidence only (set RUN_SIMULATOR=1 to run marker)"
  exit 0
fi

xcrun simctl list runtimes >/dev/null 2>&1 || { log "SKIP: CoreSimulator unavailable"; exit 0; }
device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
[[ -n "${device_udid}" ]] || { log "SKIP: no available iPhone Simulator"; exit 0; }
app_id="com.modular.mojo.ios.core-seed-probe"
app_path="${output_root}/core_seed_probe.app"
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
grep -qx 'MOJO_COMPILERRT_CORE_SEED_PROBE_PASS' "${output_root}/launch.log" || fail "missing core seed marker"
log "PASS: bounded non-AsyncRT core seed completed"
log "No throwing, stack collection, initialize_runtime, AsyncRT, or general runtime claim."
