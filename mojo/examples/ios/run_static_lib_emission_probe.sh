#!/usr/bin/env bash
# Verify repository-built Mojo static-library emission for both iOS triples.
# This is archive/object metadata evidence only: it does not link, sign, or run.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_STATIC_LIB_OUT:-${repo_root}/bazel-out/ios-static-lib-emission-probe}"

log() {
  printf '[ios-static-lib-emission-probe] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

[[ -x "${mojo_bin}" ]] || fail "MOJO_BIN is not executable: ${mojo_bin}"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is not a directory: ${stdlib_path}"
command -v ar >/dev/null 2>&1 || fail "ar is required"
command -v vtool >/dev/null 2>&1 || fail "vtool is required"
mkdir -p "${output_root}"

build_one() {
  local target_triple="$1"
  local target_cpu="$2"
  local expected_platform="$3"
  local archive_path="${output_root}/libmojo_ios_smoke_${target_triple}.a"
  local members_dir
  local member_count=0

  log "compiler: ${mojo_bin} ($(${mojo_bin} --version))"
  log "emitting static library: ${target_triple} (${target_cpu})"
  "${mojo_bin}" build \
    --target-triple "${target_triple}" \
    --target-cpu "${target_cpu}" \
    -I "${stdlib_path}" \
    --emit static-lib "${script_dir}/mojo_ios_smoke.mojo" \
    -o "${archive_path}"

  [[ -s "${archive_path}" ]] || fail "static library was not created: ${archive_path}"
  ar -t "${archive_path}" | tee "${archive_path}.members.txt"
  grep -q '\.o$' "${archive_path}.members.txt" || fail "archive has no object member: ${archive_path}"
  nm -gU "${archive_path}" | grep -q '_mojo_add$' || fail "missing _mojo_add: ${archive_path}"
  nm -gU "${archive_path}" | grep -q '_mojo_hello_utf8$' || fail "missing _mojo_hello_utf8: ${archive_path}"

  members_dir="$(mktemp -d "${output_root}/members.${target_triple}.XXXXXX")"
  (cd "${members_dir}" && ar -x "${archive_path}")
  for member_path in "${members_dir}"/*.o; do
    [[ -f "${member_path}" ]] || continue
    member_count=$((member_count + 1))
    build_metadata="$(vtool -show-build "${member_path}")"
    printf '%s\n' "${build_metadata}" | sed -n '1,40p'
    printf '%s\n' "${build_metadata}" | grep -q "platform ${expected_platform}" || \
      fail "member has unexpected platform metadata: ${member_path}"
  done
  [[ "${member_count}" -gt 0 ]] || fail "archive extraction found no object members: ${archive_path}"
  log "PASS: ${target_triple} archive has expected symbols and ${expected_platform} object metadata"
}

build_one "arm64-apple-ios17.0-simulator" "apple-m1" "IOSSIMULATOR"
build_one "arm64-apple-ios17.0" "apple-a7" "IOS"
log "Archive/object metadata evidence only; it does not establish linking, signing, installation, or execution."
