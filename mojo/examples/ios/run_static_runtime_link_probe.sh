#!/usr/bin/env bash
# Compile a String-allocating Mojo C ABI export for the iOS Simulator and link
# it only when a proposed target-compatible static CompilerRT is supplied.
# This is a D6 diagnostic, not proof that a runtime archive is app-safe.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-mojo}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
target_triple="${MOJO_IOS_RUNTIME_TRIPLE:-arm64-apple-ios17.0-simulator}"
target_cpu="${MOJO_IOS_RUNTIME_CPU:-apple-m1}"
output_root="${MOJO_IOS_RUNTIME_PROBE_OUT:-${repo_root}/bazel-out/ios-static-runtime-probe}"
runtime_archive="${MOJO_IOS_COMPILERRT_ARCHIVE:-}"
allocator_source="${MOJO_IOS_COMPILERRT_ALLOCATOR_SOURCE:-${repo_root}/KGEN/lib/CompilerRT/MemoryIOS.cpp}"

log() {
  printf '[ios-static-runtime-probe] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${mojo_bin}" >/dev/null 2>&1 || fail "MOJO_BIN='${mojo_bin}' was not found"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is not a directory: ${stdlib_path}"
mojo_path="$(command -v "${mojo_bin}")"
compiler_hash="$(shasum -a 256 "${mojo_path}" | awk '{print $1}')"

case "${target_triple}" in
  *-simulator)
    sdk_name="iphonesimulator"
    minimum_os_flag="-mios-simulator-version-min=17.0"
    ;;
  *)
    fail "MOJO_IOS_RUNTIME_TRIPLE must be an iOS Simulator triple: ${target_triple}"
    ;;
esac

sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
clangxx_bin="$(xcrun --sdk "${sdk_name}" --find clang++)"
libtool_bin="$(xcrun --sdk "${sdk_name}" --find libtool)"
mkdir -p "${output_root}"
object_path="${output_root}/mojo_ios_runtime_probe.o"
host_object_path="${output_root}/runtime_probe_main.o"
allocator_object_path="${output_root}/CompilerRTIOSAllocator.o"
allocator_archive_path="${output_root}/libCompilerRTIOSAllocator.a"
executable_path="${output_root}/mojo_ios_runtime_probe"
undefined_path="${output_root}/mojo_ios_runtime_probe.undefined.txt"

log "compiler: ${mojo_path} ($(${mojo_path} --version))"
log "compiler sha256: ${compiler_hash}"
log "stdlib: ${stdlib_path}"
log "target: ${target_triple} (${target_cpu})"
log "SDK: ${sdk_path}"
log "emitting String/allocation probe object"
"${mojo_path}" build \
  --target-triple "${target_triple}" \
  --target-cpu "${target_cpu}" \
  -I "${stdlib_path}" \
  --emit object "${script_dir}/mojo_ios_runtime_probe.mojo" \
  -o "${object_path}"

nm -u "${object_path}" | sort | tee "${undefined_path}"
for expected_symbol in _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree; do
  grep -qx "${expected_symbol}" "${undefined_path}" || \
    fail "runtime-using object is missing expected symbol: ${expected_symbol}"
done
file "${object_path}"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${object_path}" | sed -n '1,40p'
fi

[[ -f "${allocator_source}" ]] || fail "MOJO_IOS_COMPILERRT_ALLOCATOR_SOURCE does not exist: ${allocator_source}"
if [[ -n "${runtime_archive}" ]]; then
  [[ -f "${runtime_archive}" ]] || fail "MOJO_IOS_COMPILERRT_ARCHIVE does not exist: ${runtime_archive}"
fi

log "compiling libc-only CompilerRT allocator slice for the Simulator SDK"
"${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  "${minimum_os_flag}" -arch arm64 -std=c++17 \
  -DMODULAR_BUILDING_COMPILERRT -I"${repo_root}/Support/include" \
  -c "${allocator_source}" -o "${allocator_object_path}"
"${libtool_bin}" -static -o "${allocator_archive_path}" "${allocator_object_path}"
file "${allocator_object_path}" "${allocator_archive_path}"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${allocator_object_path}" | sed -n '1,40p'
fi

log "compiling native C consumer"
"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  "${minimum_os_flag}" -arch arm64 -I"${script_dir}" \
  -c "${script_dir}/runtime_probe_main.c" -o "${host_object_path}"

link_inputs=("${host_object_path}" "${object_path}" "${allocator_archive_path}")
if [[ -n "${runtime_archive}" ]]; then
  link_inputs+=("${runtime_archive}")
fi
log "linking Simulator allocator slice${runtime_archive:+ and proposed static runtime archive}"
"${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  "${minimum_os_flag}" -arch arm64 "${link_inputs[@]}" -o "${executable_path}"

if nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_'; then
  fail "linked executable still has unresolved KGEN_CompilerRT symbols"
fi
file "${executable_path}"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${executable_path}" | sed -n '1,40p'
fi
log "PASS: link completed without unresolved KGEN_CompilerRT symbols"

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log "PASS: Simulator compile/link evidence only (set RUN_SIMULATOR=1 to package, install, and launch)"
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
command -v codesign >/dev/null 2>&1 || fail "codesign is required for Simulator launch"

app_id="com.modular.mojo.ios.runtime-probe"
app_path="${output_root}/mojo_ios_runtime_probe.app"
launch_log="${output_root}/launch.log"
log "packaging and ad-hoc signing Simulator app"
rm -rf "${app_path}"
mkdir -p "${app_path}"
cp "${script_dir}/Info.plist" "${app_path}/Info.plist"
cp "${executable_path}" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
codesign --verify --deep --strict "${app_path}"

log "booting ${device_udid}"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
log "installing ${app_path}"
xcrun simctl install "${device_udid}" "${app_path}"
log "launching allocator/String probe; required marker proves assertion and lifetime completed"
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${launch_log}"
grep -qx 'MOJO_RUNTIME_STRING_PROBE_PASS' "${launch_log}" || \
  fail "Simulator launch did not emit MOJO_RUNTIME_STRING_PROBE_PASS"
log "PASS: Simulator allocator/String lifetime probe completed"
log "This does not prove initialize_runtime, AsyncRT, or broader runtime support."
