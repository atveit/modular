#!/usr/bin/env bash
# Compile/link/run the separate GlobalsIOS candidate on the iOS Simulator.
# This is basic ABI/lifecycle evidence, not a replacement for Globals.cpp.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_GLOBALS_IOS_CANDIDATE_OUT:-${repo_root}/bazel-out/ios-globals-ios-candidate}"
bazel_wrapper="${repo_root}/bazelw"

log() { printf '[ios-globals-ios-candidate] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
[[ -x "${bazel_wrapper}" ]] || fail "bazelw is required"
mkdir -p "${output_root}"

"${bazel_wrapper}" build --config=build-mojo //KGEN:CompilerRTIOSBootstrapHost
exec_root="$("${bazel_wrapper}" info --config=build-mojo execution_root)"
bazel_bin="$("${bazel_wrapper}" info --config=build-mojo bazel-bin)"
llvm_source_include="${exec_root}/external/+llvm_configure+llvm-project/llvm/include"
llvm_generated_include="${bazel_bin}/external/+llvm_configure+llvm-project/llvm/include"
[[ -d "${llvm_source_include}" ]] || fail "missing LLVM source headers"
[[ -d "${llvm_generated_include}" ]] || fail "missing generated LLVM headers"

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clangxx_bin="$(xcrun --sdk iphonesimulator --find clang++)"
libtool_bin="$(xcrun --sdk iphonesimulator --find libtool)"
target_triple="arm64-apple-ios17.0-simulator"
common_flags=(-target "${target_triple}" -isysroot "${sdk_path}"
  -mios-simulator-version-min=17.0 -arch arm64 -std=c++20
  -DMODULAR_BUILDING_COMPILERRT -I"${repo_root}/Support/include"
  -isystem "${llvm_source_include}" -isystem "${llvm_generated_include}")

candidate_object="${output_root}/GlobalsIOS.o"
allocator_object="${output_root}/MemoryIOS.o"
initialize_object="${output_root}/Initialize.o"
archive_path="${output_root}/libKGENCompilerRTIOSGlobalsCandidate.a"
consumer_object="${output_root}/globals_ios_candidate_main.o"
executable_path="${output_root}/globals_ios_candidate"

log "SDK-compiling separate candidate and narrow dependencies"
"${clangxx_bin}" "${common_flags[@]}" -c "${repo_root}/KGEN/lib/CompilerRT/GlobalsIOS.cpp" -o "${candidate_object}"
"${clangxx_bin}" "${common_flags[@]}" -c "${repo_root}/KGEN/lib/CompilerRT/MemoryIOS.cpp" -o "${allocator_object}"
"${clangxx_bin}" "${common_flags[@]}" -c "${repo_root}/KGEN/lib/CompilerRT/Initialize.cpp" -o "${initialize_object}"
for object_path in "${candidate_object}" "${allocator_object}" "${initialize_object}"; do
  vtool -show-build "${object_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong platform: ${object_path}"
done
"${libtool_bin}" -static -o "${archive_path}" "${candidate_object}" "${allocator_object}" "${initialize_object}"

log "compiling exact llvm::StringRef ABI consumer"
"${clangxx_bin}" "${common_flags[@]}" -c "${script_dir}/compilerrt_globals_ios_candidate_main.cpp" -o "${consumer_object}"
"${clangxx_bin}" "${common_flags[@]}" "${consumer_object}" "${archive_path}" -o "${executable_path}"
nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_' && fail "residual CompilerRT symbol"
vtool -show-build "${executable_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong executable platform"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: compile/link ABI candidate evidence only (set RUN_SIMULATOR=1 to run lifecycle checks)"
  exit 0
fi

xcrun simctl list runtimes >/dev/null 2>&1 || { log "SKIP: CoreSimulator unavailable"; exit 0; }
device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
[[ -n "${device_udid}" ]] || { log "SKIP: no available iPhone Simulator"; exit 0; }
app_id="com.modular.mojo.ios.globals-ios-candidate"
app_path="${output_root}/globals_ios_candidate.app"
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
grep -qx 'MOJO_COMPILERRT_GLOBALS_IOS_CANDIDATE_PASS' "${output_root}/launch.log" || fail "missing lifecycle marker"
log "PASS: Simulator synchronized named/indexed global stress completed"
log "The iOS core is mutex-based, not lock-free; no AsyncRT or contention-performance claim."
