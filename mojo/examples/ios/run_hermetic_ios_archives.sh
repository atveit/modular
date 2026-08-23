#!/bin/bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd "${script_dir}/../../.." && pwd)"
readonly jobs="${MOJO_IOS_BAZEL_JOBS:-16}"
readonly consumer="//mojo/examples/ios:hermetic_ios_archive_consumer"
readonly core_target="//mojo/examples/ios:compilerrt_ios_core"
readonly mojo_target="//mojo/examples/ios:mojo_ios_archive"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: hermetic iOS archive validation requires Xcode on macOS"
  exit 0
fi

readonly work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mojo-ios-hermetic.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

check_archive_members() {
  local archive="$1"
  local expected_platform="$2"
  local extract_dir="$3"
  mkdir -p "${extract_dir}"
  (
    cd "${extract_dir}"
    ar -x "${archive}"
  )
  local found=0
  while IFS= read -r object; do
    found=1
    local metadata
    metadata="$(vtool -show-build "${object}")"
    grep -Eq "platform[[:space:]]+${expected_platform}$" <<<"${metadata}"
    grep -Eq "minos[[:space:]]+17\.0$" <<<"${metadata}"
  done < <(find "${extract_dir}" -type f -name '*.o' -print)
  [[ "${found}" == 1 ]]

  # llvm-ar receives ZERO_AR_DATE from the registered toolchain.
  if ar -tv "${archive}" | grep -Ev 'Jan[[:space:]]+1[[:space:]]+[0-9:]+[[:space:]]+1970' | grep -q .; then
    echo "FAIL: nondeterministic archive timestamp in ${archive}" >&2
    ar -tv "${archive}" >&2
    exit 1
  fi
}

check_platform() {
  local platform_label="$1"
  local expected_platform="$2"
  local expected_target="$3"
  local expected_sysroot="$4"
  local label="$5"

  "${repo_root}/bazelw" build \
    --config=build-mojo \
    --jobs="${jobs}" \
    --platforms="${platform_label}" \
    "${mojo_target}" \
    "${core_target}" \
    "${consumer}"

  local output_dir="${repo_root}/bazel-bin/mojo/examples/ios"
  local mojo_archive="${output_dir}/libmojo_ios_archive.a"
  local core_archive="${output_dir}/libcompilerrt_ios_core.a"
  local executable="${output_dir}/hermetic_ios_archive_consumer"
  test -s "${mojo_archive}"
  test -s "${core_archive}"
  test -s "${executable}"

  check_archive_members "${mojo_archive}" "${expected_platform}" "${work_dir}/${label}-mojo"
  check_archive_members "${core_archive}" "${expected_platform}" "${work_dir}/${label}-core"
  nm -gU "${mojo_archive}" | grep -Eq '(_?mojo_add)$'
  nm -gU "${mojo_archive}" | grep -Eq '(_?mojo_hello_utf8)$'
  for symbol in \
    KGEN_CompilerRT_AlignedAlloc \
    KGEN_CompilerRT_AlignedFree \
    KGEN_CompilerRT_DestroyGlobals \
    KGEN_CompilerRT_GetOrCreateGlobal \
    KGEN_CompilerRT_GetStackTrace \
    KGEN_CompilerRT_Initialize \
    KGEN_CompilerRT_fprintf; do
    nm -gU "${core_archive}" | grep -Eq "(_?${symbol})$"
  done
  if nm -gU "${core_archive}" | grep -Eq 'KGEN_CompilerRT_AsyncRT_|Python|JIT|Tracy|TCMalloc'; then
    echo "FAIL: forbidden runtime family entered ${core_archive}" >&2
    exit 1
  fi

  local executable_metadata
  executable_metadata="$(vtool -show-build "${executable}")"
  grep -Eq "platform[[:space:]]+${expected_platform}$" <<<"${executable_metadata}"
  grep -Eq "minos[[:space:]]+17\.0$" <<<"${executable_metadata}"
  nm -gU "${executable}" | grep -Eq '(_?mojo_add)$'
  nm "${executable}" | grep -Eq '(_?KGEN_CompilerRT_Initialize)$'

  local mojo_action="${work_dir}/${label}-mojo-action.txt"
  local core_action="${work_dir}/${label}-core-action.txt"
  "${repo_root}/bazelw" aquery \
    --config=build-mojo \
    --platforms="${platform_label}" \
    "mnemonic(MojoIOSCompile, ${mojo_target})" \
    --output=text >"${mojo_action}"
  "${repo_root}/bazelw" aquery \
    --config=build-mojo \
    --platforms="${platform_label}" \
    "mnemonic(CppCompile, ${core_target})" \
    --output=text >"${core_action}"
  grep -Fq -- "--target-triple" "${mojo_action}"
  grep -Fq -- "${expected_target}" "${mojo_action}"
  grep -Fq -- "--target=${expected_target}" "${core_action}"
  grep -Fq -- "--sysroot=external/+apple_sysroot_repository+${expected_sysroot}/sysroot" "${core_action}"
  if grep -Eq 'xcrun|ExecutionInfo:.*(no-sandbox|local:)' "${mojo_action}" "${core_action}"; then
    echo "FAIL: undeclared Xcode discovery or sandbox escape in iOS archive action" >&2
    exit 1
  fi

  echo "PASS: ${expected_platform} sandboxed same-graph Mojo/core archives"
}

cd "${repo_root}"
check_platform \
  "@build_bazel_apple_support//platforms:ios_sim_arm64" \
  "IOSSIMULATOR" \
  "arm64-apple-ios17.0-simulator" \
  "sysroot-ios-simulator" \
  "simulator"
check_platform \
  "@build_bazel_apple_support//platforms:ios_arm64" \
  "IOS" \
  "arm64-apple-ios17.0" \
  "sysroot-ios-device" \
  "device"
