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
  *-ios*)
    sdk_name="iphoneos"
    minimum_os_flag="-miphoneos-version-min=17.0"
    ;;
  *)
    fail "MOJO_IOS_RUNTIME_TRIPLE must be an iOS device or Simulator triple: ${target_triple}"
    ;;
esac

sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
clangxx_bin="$(xcrun --sdk "${sdk_name}" --find clang++)"
mkdir -p "${output_root}"
object_path="${output_root}/mojo_ios_runtime_probe.o"
host_object_path="${output_root}/runtime_probe_main.o"
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

if [[ -z "${runtime_archive}" ]]; then
  log "SKIP: set MOJO_IOS_COMPILERRT_ARCHIVE to an iOS static runtime archive to link the probe"
  log "The undefined-symbol manifest is the expected pre-link D6 evidence."
  exit 0
fi
[[ -f "${runtime_archive}" ]] || fail "MOJO_IOS_COMPILERRT_ARCHIVE does not exist: ${runtime_archive}"

log "compiling native C consumer"
"${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  "${minimum_os_flag}" -arch arm64 -I"${script_dir}" \
  -c "${script_dir}/runtime_probe_main.c" -o "${host_object_path}"

log "linking proposed static runtime archive"
"${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
  "${minimum_os_flag}" -arch arm64 "${host_object_path}" "${object_path}" \
  "${runtime_archive}" -o "${executable_path}"

if nm -u "${executable_path}" | grep -q 'KGEN_CompilerRT_'; then
  fail "linked executable still has unresolved KGEN_CompilerRT symbols"
fi
file "${executable_path}"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${executable_path}" | sed -n '1,40p'
fi
log "PASS: link completed without unresolved KGEN_CompilerRT symbols"
log "This is link evidence only; run the app on Simulator before claiming allocation/String runtime support."
