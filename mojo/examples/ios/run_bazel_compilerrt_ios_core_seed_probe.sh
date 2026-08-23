#!/usr/bin/env bash
# Build both bounded CompilerRT iOS core-seed archives with Bazel/Xcode, then
# link them with the emitted-Mojo global and Error probes.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_BAZEL_CORE_SEED_OUT:-${repo_root}/bazel-out/ios-bazel-core-seed-probe}"
bazel_wrapper="${repo_root}/bazelw"
simulator_archive="${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core_simulator_archive.a"
device_archive="${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core_device_archive.a"

log() { printf '[ios-bazel-core-seed-probe] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[[ -x "${bazel_wrapper}" ]] || fail "bazelw is required"
mkdir -p "${output_root}/simulator" "${output_root}/device"

log "building target-correct Simulator and device archives"
"${bazel_wrapper}" build --config=build-mojo \
  //mojo/examples/ios:compilerrt_ios_core_simulator_archive \
  //mojo/examples/ios:compilerrt_ios_core_device_archive

[[ -f "${simulator_archive}" ]] || fail "missing Simulator archive: ${simulator_archive}"
[[ -f "${device_archive}" ]] || fail "missing device archive: ${device_archive}"

log "linking emitted-Mojo probes with the Bazel Simulator archive"
MOJO_IOS_CORE_SEED_ARCHIVE="${simulator_archive}" \
MOJO_IOS_CORE_SEED_PLATFORM=simulator \
MOJO_IOS_CORE_SEED_PROBE_OUT="${output_root}/simulator" \
RUN_SIMULATOR="${RUN_SIMULATOR:-0}" \
  "${script_dir}/run_compilerrt_ios_core_seed_probe.sh"

log "linking emitted-Mojo probes with the Bazel device archive"
MOJO_IOS_CORE_SEED_ARCHIVE="${device_archive}" \
MOJO_IOS_CORE_SEED_PLATFORM=device \
MOJO_IOS_CORE_SEED_PROBE_OUT="${output_root}/device" \
RUN_SIMULATOR=0 \
  "${script_dir}/run_compilerrt_ios_core_seed_probe.sh"

log "PASS: both Bazel-produced archives passed member metadata, symbol, and emitted-Mojo link gates"
log "The Simulator runs only with RUN_SIMULATOR=1; device signing/launch and AsyncRT remain out of scope."
