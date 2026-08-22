#!/usr/bin/env bash
# Compile-only iOS SIMD assembly evidence. This verifies target directives and
# explicit NEON vector mnemonics, not correctness, linking, or performance.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_SIMD_ASM_OUT:-${repo_root}/bazel-out/ios-simd-assembly-probe}"

log() {
  printf '[ios-simd-assembly-probe] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

[[ -x "${mojo_bin}" ]] || fail "MOJO_BIN is not executable: ${mojo_bin}"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is not a directory: ${stdlib_path}"
mkdir -p "${output_root}"

build_one() {
  local target_triple="$1"
  local target_cpu="$2"
  local platform_directive="$3"
  local output_path="${output_root}/${target_triple}.s"

  log "compiler: ${mojo_bin} ($(${mojo_bin} --version))"
  log "emitting assembly: ${target_triple} (${target_cpu})"
  "${mojo_bin}" build \
    --target-triple "${target_triple}" \
    --target-cpu "${target_cpu}" \
    -I "${stdlib_path}" \
    --emit asm "${script_dir}/mojo_ios_simd_assembly_probe.mojo" \
    -o "${output_path}"

  grep -Eq "^[[:space:]]*\.build_version[[:space:]]+${platform_directive},[[:space:]]+17" "${output_path}" || \
    fail "missing ${platform_directive} iOS 17 build directive: ${output_path}"
  grep -Eq "^[[:space:]]*(fadd|fmul|fmla)\.4s[[:space:]]+v[0-9]+" "${output_path}" || \
    fail "missing explicit four-lane NEON floating-point arithmetic: ${output_path}"
  grep -q '_mojo_ios_simd_weighted_sum' "${output_path}" || \
    fail "missing C ABI export: ${output_path}"
  log "PASS: ${target_triple} has iOS metadata and explicit NEON arithmetic"
}

build_one "arm64-apple-ios17.0-simulator" "apple-m1" "iossimulator"
build_one "arm64-apple-ios17.0" "apple-a7" "ios"
log "Compile-only instruction evidence; it does not establish performance or runtime support."
