#!/usr/bin/env bash
# Link an emitted Mojo std.ffi._Global probe with the separate SDK-native
# GlobalsIOS candidate. This is not initialize_runtime or AsyncRT coverage.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_GLOBALS_MOJO_PROBE_OUT:-${repo_root}/bazel-out/ios-globals-mojo-probe}"
candidate_root="${output_root}/candidate"
candidate_archive="${candidate_root}/libKGENCompilerRTIOSGlobalsCandidate.a"

log() { printf '[ios-globals-mojo-probe] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[[ -x "${mojo_bin}" ]] || fail "MOJO_BIN is unavailable: ${mojo_bin}"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is unavailable: ${stdlib_path}"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
mkdir -p "${output_root}"

log "building separate SDK-native GlobalsIOS candidate archive"
RUN_SIMULATOR=0 MOJO_IOS_GLOBALS_IOS_CANDIDATE_OUT="${candidate_root}" \
  "${script_dir}/run_compilerrt_ios_globals_ios_candidate.sh"
[[ -f "${candidate_archive}" ]] || fail "candidate archive is missing: ${candidate_archive}"

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clang_bin="$(xcrun --sdk iphonesimulator --find clang)"
clangxx_bin="$(xcrun --sdk iphonesimulator --find clang++)"
target_triple="arm64-apple-ios17.0-simulator"
mojo_object="${output_root}/mojo_ios_global_symbol_probe.o"
consumer_object="${output_root}/globals_mojo_probe_main.o"
executable_path="${output_root}/globals_mojo_probe"

log "emitting real Mojo std.ffi._Global object"
MOJO_CRASHPAD=0 "${mojo_bin}" build \
  --target-triple "${target_triple}" --target-cpu apple-m1 \
  -I "${stdlib_path}" --emit object \
  "${script_dir}/mojo_ios_global_symbol_probe.mojo" -o "${mojo_object}"
nm -u "${mojo_object}" | sort | tee "${output_root}/mojo.undefined.txt"
for symbol in _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree _KGEN_CompilerRT_GetOrCreateGlobal; do
  grep -qx "${symbol}" "${output_root}/mojo.undefined.txt" || fail "missing ${symbol}"
done
vtool -show-build "${mojo_object}" | grep -q 'platform IOSSIMULATOR' || fail "wrong Mojo object platform"

log "compiling C consumer and linking candidate archive"
"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  -c "${script_dir}/compilerrt_globals_mojo_probe_main.c" -o "${consumer_object}"
"${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 \
  "${consumer_object}" "${mojo_object}" "${candidate_archive}" -o "${executable_path}"
nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_' && fail "residual CompilerRT symbol"
vtool -show-build "${executable_path}" | grep -q 'platform IOSSIMULATOR' || fail "wrong executable platform"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: compile/link emitted-global evidence only (set RUN_SIMULATOR=1 to run lifecycle marker)"
  exit 0
fi

xcrun simctl list runtimes >/dev/null 2>&1 || { log "SKIP: CoreSimulator unavailable"; exit 0; }
device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
[[ -n "${device_udid}" ]] || { log "SKIP: no available iPhone Simulator"; exit 0; }
app_id="com.modular.mojo.ios.globals-mojo-probe"
app_path="${output_root}/globals_mojo_probe.app"
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
grep -qx 'MOJO_COMPILERRT_GLOBALS_MOJO_PROBE_PASS' "${output_root}/launch.log" || fail "missing lifecycle marker"
log "PASS: emitted Mojo global path and basic teardown completed"
log "No initialize_runtime, AsyncRT, or general runtime support claim."
