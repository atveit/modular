#!/usr/bin/env bash
# Emit object/symbol manifests for narrow stdlib runtime dependencies on iOS.
# This fixture never links, packages, signs, installs, or executes an artifact.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
default_compiler="${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full"
mojo_bin="${MOJO_IOS_STDLIB_MANIFEST_MOJO:-${MOJO_BIN:-${default_compiler}}}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
output_root="${MOJO_IOS_STDLIB_MANIFEST_OUT:-/tmp/mojo-ios-stdlib-symbol-manifests}"

log() { printf '[mojo-ios-stdlib-manifests] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

if [[ "${mojo_bin}" == */* ]]; then
  [[ -x "${mojo_bin}" ]] || fail "compiler is unavailable: ${mojo_bin}"
  mojo_path="${mojo_bin}"
else
  command -v "${mojo_bin}" >/dev/null 2>&1 || fail "MOJO_BIN='${mojo_bin}' was not found"
  mojo_path="$(command -v "${mojo_bin}")"
fi
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is not a directory: ${stdlib_path}"
compiler_hash="$(shasum -a 256 "${mojo_path}" | awk '{print $1}')"
mkdir -p "${output_root}"

log "compiler: ${mojo_path} ($(${mojo_path} --version))"
log "compiler sha256: ${compiler_hash}"
log "stdlib: ${stdlib_path}"
log "scope: object/symbol manifests only; no link or runtime claim"

assert_exact_manifest() {
  local probe_name="$1"
  local manifest_path="$2"
  local allowed_path="${manifest_path%.txt}.allowed.txt"
  local allowed_symbols=()
  case "${probe_name}" in
    string)
      allowed_symbols=(
        _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree
        _dup _fclose _fdopen _fflush _memcpy _write
      )
      ;;
    error)
      allowed_symbols=(
        _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree
        _KGEN_CompilerRT_GetStackTrace
        _dup _fclose _fdopen _fflush _memcpy _write
      )
      ;;
    global)
      allowed_symbols=(
        _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree
        _KGEN_CompilerRT_GetOrCreateGlobal
        _dup _fclose _fdopen _fflush _memcpy _write
      )
      ;;
    environment-file)
      allowed_symbols=(
        _KGEN_CompilerRT_AlignedAlloc _KGEN_CompilerRT_AlignedFree
        _KGEN_CompilerRT_GetStackTrace _KGEN_CompilerRT_fprintf
        ___error _clock_gettime_nsec_np _close _dup _fclose _fdopen _fflush _getenv _lstat
        _memcpy _mkdir _open _read _setenv _stat _strerror _unsetenv _write
      )
      ;;
    *)
      fail "no audited allow-list for ${probe_name}"
      ;;
  esac
  printf '%s\n' "${allowed_symbols[@]}" | sort > "${allowed_path}"
  diff -u "${allowed_path}" "${manifest_path}" || \
    fail "${probe_name} undefined-symbol contract changed"
}

emit_probe() {
  local target_label="$1"
  local target_triple="$2"
  local target_cpu="$3"
  local expected_platform="$4"
  local probe_name="$5"
  local source_path="$6"
  shift 6
  local object_path="${output_root}/${target_label}-${probe_name}.o"
  local manifest_path="${output_root}/${target_label}-${probe_name}.undefined.txt"

  log "emitting ${probe_name} for ${target_triple} (${target_cpu})"
  "${mojo_path}" build \
    --target-triple "${target_triple}" \
    --target-cpu "${target_cpu}" \
    -I "${stdlib_path}" \
    --emit object "${source_path}" \
    -o "${object_path}"

  nm -u "${object_path}" | sort | tee "${manifest_path}"
  if grep -q '^_KGEN_CompilerRT_AsyncRT_' "${manifest_path}"; then
    fail "${probe_name} unexpectedly depends on AsyncRT"
  fi
  for expected_symbol in "$@"; do
    grep -qx "${expected_symbol}" "${manifest_path}" || \
      fail "${probe_name} is missing expected symbol: ${expected_symbol}"
  done
  assert_exact_manifest "${probe_name}" "${manifest_path}"
  file "${object_path}"
  if command -v vtool >/dev/null 2>&1; then
    vtool -show-build "${object_path}" | sed -n '1,40p'
    vtool -show-build "${object_path}" | grep -q "platform ${expected_platform}" || \
      fail "wrong platform metadata for ${object_path}"
  fi
  log "PASS: recorded ${probe_name} symbol manifest for ${target_label}"
}

for target_spec in \
  'simulator arm64-apple-ios17.0-simulator apple-m1 IOSSIMULATOR' \
  'device arm64-apple-ios17.0 apple-a7 IOS'; do
  read -r target_label target_triple target_cpu expected_platform <<<"${target_spec}"
  emit_probe \
    "${target_label}" "${target_triple}" "${target_cpu}" "${expected_platform}" \
    string "${script_dir}/mojo_ios_runtime_probe.mojo" \
    _KGEN_CompilerRT_AlignedAlloc \
    _KGEN_CompilerRT_AlignedFree
  emit_probe \
    "${target_label}" "${target_triple}" "${target_cpu}" "${expected_platform}" \
    error "${script_dir}/mojo_ios_error_symbol_probe.mojo" \
    _KGEN_CompilerRT_AlignedAlloc \
    _KGEN_CompilerRT_AlignedFree \
    _KGEN_CompilerRT_GetStackTrace
  emit_probe \
    "${target_label}" "${target_triple}" "${target_cpu}" "${expected_platform}" \
    global "${script_dir}/mojo_ios_global_symbol_probe.mojo" \
    _KGEN_CompilerRT_AlignedAlloc \
    _KGEN_CompilerRT_AlignedFree \
    _KGEN_CompilerRT_GetOrCreateGlobal
  emit_probe \
    "${target_label}" "${target_triple}" "${target_cpu}" "${expected_platform}" \
    environment-file "${script_dir}/mojo_ios_file_probe.mojo" \
    _KGEN_CompilerRT_AlignedAlloc \
    _KGEN_CompilerRT_AlignedFree \
    _KGEN_CompilerRT_GetStackTrace \
    _KGEN_CompilerRT_fprintf \
    _clock_gettime_nsec_np \
    _getenv \
    _open \
    _read \
    _setenv \
    _unsetenv \
    _write
done

log 'PASS: serial runtime contracts for both iOS targets contain no AsyncRT dependency.'
