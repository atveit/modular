#!/usr/bin/env bash
# Compile-only iOS stdlib coverage for both arm64 Apple target triples.
# This fixture does not link, package, sign, install, or execute its outputs.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
mojo_bin="${MOJO_BIN:-mojo}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_STDLIB_COVERAGE_OUT:-/tmp/mojo-ios-stdlib-compile-coverage}"

log() { printf '[mojo-ios-stdlib-coverage] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${mojo_bin}" >/dev/null 2>&1 || fail "MOJO_BIN='${mojo_bin}' was not found"
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is not a directory: ${stdlib_path}"
mojo_path="$(command -v "${mojo_bin}")"
compiler_hash="$(shasum -a 256 "${mojo_path}" | awk '{print $1}')"
mkdir -p "${output_root}"

log "compiler: ${mojo_path} ($(${mojo_path} --version))"
log "compiler sha256: ${compiler_hash}"
log "stdlib: ${stdlib_path}"
log "scope: LLVM emission only; no link, runtime, signing, device, or Simulator execution"

build_target() {
  local label="$1"
  local target_triple="$2"
  local target_cpu="$3"
  local output_path="${output_root}/${label}.ll"

  log "emitting LLVM for ${target_triple} (${target_cpu})"
  "${mojo_path}" build \
    --target-triple "${target_triple}" \
    --target-cpu "${target_cpu}" \
    -I "${stdlib_path}" \
    --emit llvm \
    "${script_dir}/mojo_ios_stdlib_compile_coverage.mojo" \
    -o "${output_path}"

  [[ -s "${output_path}" ]] || fail "LLVM output is missing: ${output_path}"
  grep -q '@mojo_ios_stdlib_compile_coverage' "${output_path}" || fail "C ABI export is absent: ${output_path}"
  grep -q '@__error' "${output_path}" || fail "Darwin errno lowering is absent: ${output_path}"
  grep -q '@clock_gettime_nsec_np' "${output_path}" || fail "Darwin clock lowering is absent: ${output_path}"
  grep -q '@KGEN_CompilerRT_AlignedFree' "${output_path}" || fail "format/output runtime dependency is absent: ${output_path}"
  grep -q '@write' "${output_path}" || fail "libc output lowering is absent: ${output_path}"
  grep -E '^(define|declare).*@(mojo_ios_stdlib_compile_coverage|__error|clock_gettime_nsec_np|KGEN_CompilerRT_AlignedFree|write)' "${output_path}"
  log "PASS: compile-only evidence recorded at ${output_path}"
}

build_target simulator arm64-apple-ios17.0-simulator apple-m1
build_target device arm64-apple-ios17.0 apple-a7

log 'PASS: both iOS triples compiled; this is not a claim that the stdlib fixture can link or run.'
