#!/usr/bin/env bash
# Record the iOS Simulator native symbol names used by the checked-in
# std.runtime.initialize_runtime implementation. This is a D7 source/dependency
# discovery fixture, not an ABI-signature, runtime-link, or execution test.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
default_compiler="${repo_root}/bazel-bin/KGEN/tools/mojo/mojo-full"
mojo_bin="${MOJO_IOS_RUNTIME_INIT_MOJO:-${MOJO_BIN:-${default_compiler}}}"
stdlib_path="${MOJO_STDLIB_PATH:-${repo_root}/mojo/stdlib}"
target_triple="${MOJO_IOS_RUNTIME_INIT_TRIPLE:-arm64-apple-ios17.0-simulator}"
target_cpu="${MOJO_IOS_RUNTIME_INIT_CPU:-apple-m1}"
output_root="${MOJO_IOS_RUNTIME_INIT_OUT:-${repo_root}/bazel-out/ios-runtime-init-manifest}"

log() {
  printf '[ios-runtime-init-manifest] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

if [[ "${mojo_bin}" == */* ]]; then
  [[ -x "${mojo_bin}" ]] || fail "pinned compiler is unavailable: ${mojo_bin}; build it with ./bazelw build --config=build-mojo //KGEN:mojo"
else
  command -v "${mojo_bin}" >/dev/null 2>&1 || fail "MOJO_BIN='${mojo_bin}' was not found"
fi
[[ -d "${stdlib_path}" ]] || fail "MOJO_STDLIB_PATH is not a directory: ${stdlib_path}"
case "${target_triple}" in
  *-simulator) ;;
  *) fail "MOJO_IOS_RUNTIME_INIT_TRIPLE must be an iOS Simulator triple: ${target_triple}" ;;
esac

mkdir -p "${output_root}"
object_path="${output_root}/mojo_ios_runtime_init_probe.o"
manifest_path="${output_root}/mojo_ios_runtime_init_probe.undefined.txt"
if [[ "${mojo_bin}" == */* ]]; then
  mojo_path="${mojo_bin}"
else
  mojo_path="$(command -v "${mojo_bin}")"
fi

log "compiler: ${mojo_path} ($(${mojo_path} --version))"
log "stdlib: ${stdlib_path}"
log "target: ${target_triple} (${target_cpu})"
log "emitting initialize_runtime symbol-reference object (no link or execution)"
"${mojo_path}" build \
  --target-triple "${target_triple}" \
  --target-cpu "${target_cpu}" \
  -I "${stdlib_path}" \
  --emit object "${script_dir}/mojo_ios_runtime_init_probe.mojo" \
  -o "${object_path}"

nm -u "${object_path}" | sort | tee "${manifest_path}"
expected_symbols=(
  _KGEN_CompilerRT_AsyncRT_GetCurrentCPUDevice
  _KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice
  _KGEN_CompilerRT_AsyncRT_ReleaseCPUDevice
)
for symbol in "${expected_symbols[@]}"; do
  grep -qx "${symbol}" "${manifest_path}" || fail "missing expected runtime-init symbol: ${symbol}"
done

file "${object_path}"
if command -v vtool >/dev/null 2>&1; then
  vtool -show-build "${object_path}" | sed -n '1,40p'
fi
log "PASS: emitted Simulator symbol manifest only"
log "This does not validate ABI signatures, a static AsyncRT archive, a successful link, or runtime execution."
