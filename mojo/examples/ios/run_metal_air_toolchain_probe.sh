#!/usr/bin/env bash
# Artifact-only Xcode Metal/AIR probe. It does not build Mojo GPU code, package
# an app, load a library, or dispatch a kernel. Unsupported candidates SKIP.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="${MOJO_IOS_METAL_AIR_PROBE_OUT:-/tmp/mojo-ios-metal-air-probe}"
targets="${MOJO_IOS_METAL_AIR_TARGETS:-air64-apple-ios17.0 air64-apple-ios17.0-simulator}"
source_path="${MOJO_IOS_METAL_AIR_SOURCE:-${script_dir}/metal_air_probe_kernel.metal}"

log() { printf '[mojo-ios-metal-air-probe] %s\n' "$*"; }

record_command() {
  local command_file="$1"
  shift
  printf '$' >>"${command_file}"
  printf ' %q' "$@" >>"${command_file}"
  printf '\n' >>"${command_file}"
}

if ! command -v xcrun >/dev/null 2>&1; then
  log 'SKIP: xcrun is unavailable; no Apple Metal toolchain was probed'
  exit 0
fi
if [[ ! -f "${source_path}" ]]; then
  log "SKIP: MSL source is unavailable: ${source_path}"
  exit 0
fi

mkdir -p "${output_root}"
log "output: ${output_root}"
log "candidates: ${targets}"
probed=0
artifacts=0
skipped=0

for target in ${targets}; do
  case "${target}" in
    air64-apple-ios*-simulator) sdk_name='iphonesimulator' ;;
    air64-apple-ios*) sdk_name='iphoneos' ;;
    *)
      log "SKIP: ${target}: not a recognized candidate iOS AIR triple"
      skipped=$((skipped + 1))
      continue
      ;;
  esac

  target_dir="${output_root}/${target//[^A-Za-z0-9]/_}"
  command_file="${target_dir}/commands.txt"
  compile_log="${target_dir}/metal-compile.log"
  link_log="${target_dir}/metallib-link.log"
  inspect_log="${target_dir}/inspect.log"
  air_path="${target_dir}/probe.air"
  metallib_path="${target_dir}/probe.metallib"
  mkdir -p "${target_dir}"
  : >"${command_file}"
  : >"${compile_log}"
  : >"${link_log}"
  : >"${inspect_log}"

  metal_bin="$(xcrun --sdk "${sdk_name}" --find metal 2>/dev/null || true)"
  metallib_bin="$(xcrun --sdk "${sdk_name}" --find metallib 2>/dev/null || true)"
  if [[ -z "${metal_bin}" || -z "${metallib_bin}" ]]; then
    log "SKIP: ${target}: metal/metallib unavailable in ${sdk_name}"
    skipped=$((skipped + 1))
    continue
  fi

  probed=$((probed + 1))
  log "probe: ${target} via ${sdk_name}"
  record_command "${command_file}" "${metal_bin}" -c -target "${target}" "${source_path}" -o "${air_path}"
  if ! "${metal_bin}" -c -target "${target}" "${source_path}" -o "${air_path}" >"${compile_log}" 2>&1; then
    log "SKIP: ${target}: metal rejected target; see ${compile_log}"
    skipped=$((skipped + 1))
    continue
  fi
  record_command "${command_file}" "${metallib_bin}" "${air_path}" -o "${metallib_path}"
  if ! "${metallib_bin}" "${air_path}" -o "${metallib_path}" >"${link_log}" 2>&1; then
    log "SKIP: ${target}: metallib rejected AIR; see ${link_log}"
    skipped=$((skipped + 1))
    continue
  fi
  record_command "${command_file}" file "${air_path}" "${metallib_path}"
  file "${air_path}" "${metallib_path}" >>"${inspect_log}" 2>&1 || true
  record_command "${command_file}" xcrun --sdk "${sdk_name}" --show-sdk-path
  xcrun --sdk "${sdk_name}" --show-sdk-path >>"${inspect_log}" 2>&1 || true
  log "ARTIFACT-ONLY: ${target}: created AIR and metallib in ${target_dir}"
  artifacts=$((artifacts + 1))
done

log "summary: probed=${probed} artifact-only=${artifacts} skipped=${skipped}"
log 'This does not prove Mojo lowering, app packaging, library loading, or device GPU execution.'
