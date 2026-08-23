#!/usr/bin/env bash
# Link an emitted Mojo Error-construction probe with iOS allocator and the
# zero-stack-trace candidate. This does not cover throwing or stack collection.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_ERROR_PROBE_OUT:-${repo_root}/bazel-out/ios-error-probe}"
bazel_wrapper="${repo_root}/bazelw"

log() { printf '[ios-error-probe] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[[ -x "${mojo_bin}" ]] || fail "MOJO_BIN is unavailable: ${mojo_bin}"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is unavailable: ${stdlib_path}"
[[ -x "${bazel_wrapper}" ]] || fail "bazelw is required"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
mkdir -p "${output_root}"

"${bazel_wrapper}" build --config=build-mojo //KGEN:CompilerRTIOSBootstrapHost
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
allocator_object="${output_root}/MemoryIOS.o"
stacktrace_object="${output_root}/StackTraceIOS.o"
archive_path="${output_root}/libKGENCompilerRTIOSNoStackTrace.a"
mojo_object="${output_root}/mojo_ios_error_symbol_probe.o"
consumer_object="${output_root}/error_probe_main.o"
executable_path="${output_root}/error_probe"

log "SDK-compiling allocator and zero-stack-trace candidate"
"${clangxx_bin}" "${common_flags[@]}" -c "${repo_root}/KGEN/lib/CompilerRT/MemoryIOS.cpp" -o "${allocator_object}"
"${clangxx_bin}" "${common_flags[@]}" -c "${repo_root}/KGEN/lib/CompilerRT/StackTraceIOS.cpp" -o "${stacktrace_object}"
for object_path in "${allocator_object}" "${stacktrace_object}"; do
  vtool -show-build "${object_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong platform: ${object_path}"
done
"${libtool_bin}" -static -o "${archive_path}" "${allocator_object}" "${stacktrace_object}"

log "emitting Mojo Error-construction object"
MOJO_CRASHPAD=0 "${mojo_bin}" build \
  --target-triple "${target_triple}" --target-cpu apple-m1 \
  -I "${stdlib_path}" --emit object \
  "${script_dir}/mojo_ios_error_symbol_probe.mojo" -o "${mojo_object}"
nm -u "${mojo_object}" | sort | tee "${output_root}/mojo.undefined.txt"
for symbol in _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree _KGEN_CompilerRT_GetStackTrace; do
  grep -qx "${symbol}" "${output_root}/mojo.undefined.txt" || fail "missing ${symbol}"
done
vtool -show-build "${mojo_object}" | grep -q 'platform IOSSIMULATOR' || fail "wrong Mojo object platform"

log "compiling C consumer and linking error candidate archive"
"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  -c "${script_dir}/compilerrt_error_probe_main.c" -o "${consumer_object}"
"${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  "${consumer_object}" "${mojo_object}" "${archive_path}" -o "${executable_path}"
nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_' && fail "residual CompilerRT symbol"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: compile/link Error-construction evidence only (set RUN_SIMULATOR=1 to run marker)"
  exit 0
fi

xcrun simctl list runtimes >/dev/null 2>&1 || { log "SKIP: CoreSimulator unavailable"; exit 0; }
device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
[[ -n "${device_udid}" ]] || { log "SKIP: no available iPhone Simulator"; exit 0; }
app_id="com.modular.mojo.ios.error-probe"
app_path="${output_root}/error_probe.app"
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
grep -qx 'MOJO_COMPILERRT_ERROR_PROBE_PASS' "${output_root}/launch.log" || fail "missing error marker"
log "PASS: emitted Error-construction probe completed with stack traces unavailable"
log "No throwing, stack collection, initialize_runtime, or AsyncRT claim."
