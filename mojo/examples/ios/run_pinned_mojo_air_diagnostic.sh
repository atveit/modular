#!/usr/bin/env bash
# Diagnose iOS AIR target classification with a repository-built Mojo driver.
#
# This script never invokes Bazel build and never claims GPU execution. It uses
# the runtime-free iOS source so an unavailable/unsupported target diagnostic is
# not confused with the current stdlib or MAX package compatibility boundary.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_PINNED_AIR_DIAGNOSTIC_OUT:-/tmp/mojo-ios-pinned-air-diagnostic}"
targets="${MOJO_IOS_PINNED_AIR_TARGETS:-air64-apple-ios17.0 air64-apple-ios17.0-simulator}"
source_path="${MOJO_IOS_PINNED_AIR_SOURCE:-${script_dir}/mojo_ios_smoke.mojo}"
default_compiler="${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full"
mojo_bin="${MOJO_IOS_PINNED_MOJO:-${default_compiler}}"

log() { printf '[mojo-ios-pinned-air-diagnostic] %s\n' "$*"; }

record_command() {
  local command_file="$1"
  shift
  printf '$' >>"${command_file}"
  printf ' %q' "$@" >>"${command_file}"
  printf '\n' >>"${command_file}"
}

if [[ ! -f "${source_path}" ]]; then
  log "SKIP: source is unavailable: ${source_path}"
  exit 0
fi
if [[ ! -x "${mojo_bin}" ]]; then
  log "SKIP: repository-pinned compiler is unavailable: ${mojo_bin}"
  log 'Build it explicitly with ./bazelw build --config=build-mojo //KGEN:mojo, or set MOJO_IOS_PINNED_MOJO to that built executable.'
  exit 0
fi

mkdir -p "${output_root}"
provenance_path="${output_root}/compiler-provenance.txt"
: >"${provenance_path}"
printf 'compiler=%s\n' "${mojo_bin}" >>"${provenance_path}"
file "${mojo_bin}" >>"${provenance_path}" 2>&1 || true
shasum -a 256 "${mojo_bin}" >>"${provenance_path}" 2>&1 || true
"${mojo_bin}" --version >>"${provenance_path}" 2>&1 || true
log "compiler provenance: ${provenance_path}"

accepted=0
rejected=0
for target in ${targets}; do
  target_dir="${output_root}/${target//[^A-Za-z0-9]/_}"
  command_file="${target_dir}/commands.txt"
  diagnostic_path="${target_dir}/compiler.out"
  output_path="${target_dir}/probe.s"
  mkdir -p "${target_dir}"
  : >"${command_file}"
  : >"${diagnostic_path}"
  record_command "${command_file}" "${mojo_bin}" build --target-triple "${target}" --emit asm -o "${output_path}" "${source_path}"

  if "${mojo_bin}" build --target-triple "${target}" --emit asm -o "${output_path}" "${source_path}" >"${diagnostic_path}" 2>&1; then
    log "ARTIFACT-ONLY: ${target}: compiler accepted target for asm emit; inspect ${target_dir}"
    find "${target_dir}" -maxdepth 1 -type f -print >>"${diagnostic_path}" 2>&1 || true
    accepted=$((accepted + 1))
  else
    log "UNSUPPORTED/DIAGNOSTIC: ${target}: compiler exited non-zero; see ${diagnostic_path}"
    rejected=$((rejected + 1))
  fi
done

log "summary: asm-target-accepted=${accepted} diagnostics=${rejected}"
log 'No result here proves Mojo GPU lowering, AIR/metallib emission, app packaging, Metal library loading, or device execution.'
