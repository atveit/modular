#!/usr/bin/env bash
# Build a minimal iOS SDK-native CompilerRT bootstrap archive. It intentionally
# includes only self-contained allocation and initialization entry points; it
# does not substitute for the full CompilerRT or AsyncRT runtime.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_COMPILERRT_BOOTSTRAP_OUT:-${repo_root}/bazel-out/ios-compilerrt-bootstrap-probe}"

log() {
  printf '[ios-compilerrt-bootstrap-probe] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
command -v ar >/dev/null 2>&1 || fail "ar is required"
command -v vtool >/dev/null 2>&1 || fail "vtool is required"
mkdir -p "${output_root}"

# Support.cpp and Globals.cpp are intentionally excluded. Direct SDK compilation
# currently stops at repository LLVM headers (llvm/ADT/StringRef.h and
# llvm/ADT/DenseMapInfo.h respectively); do not replace them with host objects.
sources=(
  "${repo_root}/KGEN/lib/CompilerRT/MemoryIOS.cpp"
  "${repo_root}/KGEN/lib/CompilerRT/Initialize.cpp"
)

build_one() {
  local target_triple="$1"
  local sdk_name="$2"
  local minimum_os_flag="$3"
  local expected_platform="$4"
  local target_dir="${output_root}/${target_triple}"
  local archive_path="${target_dir}/libKGENCompilerRTIOSBootstrap.a"
  local members_dir sdk_path clangxx_bin libtool_bin source_path object_path build_metadata member_path
  local -a object_paths=()

  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  clangxx_bin="$(xcrun --sdk "${sdk_name}" --find clang++)"
  libtool_bin="$(xcrun --sdk "${sdk_name}" --find libtool)"
  mkdir -p "${target_dir}"
  log "SDK-native compile: ${target_triple} (${sdk_name})"
  for source_path in "${sources[@]}"; do
    object_path="${target_dir}/$(basename "${source_path}" .cpp).o"
    "${clangxx_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
      "${minimum_os_flag}" -arch arm64 -std=c++20 \
      -DMODULAR_BUILDING_COMPILERRT -I"${repo_root}/Support/include" \
      -c "${source_path}" -o "${object_path}"
    build_metadata="$(vtool -show-build "${object_path}")"
    printf '%s\n' "${build_metadata}" | sed -n '1,40p'
    printf '%s\n' "${build_metadata}" | grep -q "platform ${expected_platform}" || \
      fail "unexpected object platform: ${object_path}"
    object_paths+=("${object_path}")
  done

  "${libtool_bin}" -static -o "${archive_path}" "${object_paths[@]}"
  ar -t "${archive_path}" | tee "${archive_path}.members.txt"
  members_dir="$(mktemp -d "${target_dir}/members.XXXXXX")"
  (cd "${members_dir}" && ar -x "${archive_path}")
  for member_path in "${members_dir}"/*.o; do
    [[ -f "${member_path}" ]] || continue
    build_metadata="$(vtool -show-build "${member_path}")"
    printf '%s\n' "${build_metadata}" | sed -n '1,40p'
    printf '%s\n' "${build_metadata}" | grep -q "platform ${expected_platform}" || \
      fail "unexpected archived member platform: ${member_path}"
  done
  for expected_symbol in \
    _KGEN_CompilerRT_AlignedAlloc \
    _KGEN_CompilerRT_AlignedFree \
    _KGEN_CompilerRT_Initialize; do
    nm -gU "${archive_path}" | grep -qx ".*${expected_symbol}" || \
      fail "missing ${expected_symbol}: ${archive_path}"
  done
  log "PASS: ${archive_path} contains only SDK-built ${expected_platform} objects"
}

build_one "arm64-apple-ios17.0-simulator" "iphonesimulator" \
  "-mios-simulator-version-min=17.0" "IOSSIMULATOR"
build_one "arm64-apple-ios17.0" "iphoneos" \
  "-miphoneos-version-min=17.0" "IOS"
log "Bootstrap archive evidence only; no Globals/Support/AsyncRT, link, signing, or execution claim."
