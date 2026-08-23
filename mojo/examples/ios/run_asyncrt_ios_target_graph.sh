#!/usr/bin/env bash
# Build and audit the bounded N11 AsyncRT graph for iOS device and Simulator.
# This gate compiles and archives only. It does not link an app or claim that
# std.runtime.initialize_runtime() executes; that is the separate N12 gate.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
bazel_jobs="${MOJO_IOS_BAZEL_JOBS:-16}"

log() {
  printf '[asyncrt-ios-target-graph] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v nm >/dev/null 2>&1 || fail "nm is required"
command -v vtool >/dev/null 2>&1 || fail "vtool is required"

cd "${repo_root}"

target="//KGEN:CompilerRTIOSAsyncRTSingleThread"
targets=(
  "${target}"
  "//AsyncRT:RuntimeIOSSingleThread"
  "//Support:AsyncRTRuntimeIOS"
)
archives=(
  "bazel-bin/KGEN/libCompilerRTIOSAsyncRTSingleThread.a"
  "bazel-bin/AsyncRT/libRuntimeIOSSingleThread.a"
  "bazel-bin/Support/libAsyncRTRuntimeIOS.a"
)

deps="$(./bazelw query "deps(${target})" --output=label)"
filtered_deps="$(printf '%s\n' "${deps}" | grep -v -E \
  '(^//AsyncRT:include/AsyncRT/Runtime/Profiling.h$|^//Support:include/Support/Profiling/TimeProfilerDisabled.h$)' || true)"
if grep -Eiq 'tcmalloc|mlir|jit|crash|tracy|python|signal|plugin|process|profil' \
  <<<"${filtered_deps}"; then
  printf '%s\n' "${filtered_deps}" | grep -Ei \
    'tcmalloc|mlir|jit|crash|tracy|python|signal|plugin|process|profil' >&2
  fail "desktop/compiler dependency entered the N11 graph"
fi

for forbidden_target in \
  '@llvm-project//llvm:Support' \
  '@llvm-project//mlir:IR' \
  '//bazel/internal:tcmalloc_numa_aware'; do
  path="$(./bazelw query "somepath(${target}, ${forbidden_target})" --output=label)"
  [[ -z "${path}" ]] || fail "forbidden path to ${forbidden_target}: ${path}"
done

sources="$(./bazelw query \
  "kind(\"source file\", deps(${target}))" --output=label | grep -E '\.(c|cc|cpp)$' || true)"
if grep -Eq '(^|/)(HostSystem|Globals|RuntimeCLOptions|ThreadPoolWorkQueue|TimeProfiler)\.cpp$' \
  <<<"${sources}"; then
  printf '%s\n' "${sources}" >&2
  fail "desktop runtime source entered the N11 graph"
fi

build_and_audit() {
  local platform="$1"
  local triple="$2"
  local expected_platform="$3"

  log "building ${triple} with ${bazel_jobs} Bazel jobs"
  ./bazelw build \
    --config=build-mojo \
    --jobs="${bazel_jobs}" \
    --features= \
    --platforms="${platform}" \
    "${targets[@]}"

  for archive in "${archives[@]}"; do
    [[ -f "${archive}" ]] || fail "missing archive: ${archive}"
    MOJO_IOS_COMPILERRT_ARCHIVE="${archive}" \
      MOJO_IOS_RUNTIME_TRIPLE="${triple}" \
      "${script_dir}/check_compilerrt_ios_static_metadata.sh" >/dev/null
    if nm -u "${archive}" | grep -Eiq \
      'MLIR|tcmalloc|Crash|Signal|Plugin|JIT|DisableABIBreaking'; then
      nm -u "${archive}" | grep -Ei \
        'MLIR|tcmalloc|Crash|Signal|Plugin|JIT|DisableABIBreaking' >&2
      fail "forbidden unresolved runtime family in ${archive}"
    fi
    log "PASS: ${archive} is ${expected_platform} and has no forbidden runtime family"
  done
}

build_and_audit \
  '@build_bazel_apple_support//platforms:ios_sim_arm64' \
  'arm64-apple-ios17.0-simulator' \
  'IOSSIMULATOR'
build_and_audit \
  '@build_bazel_apple_support//platforms:ios_arm64' \
  'arm64-apple-ios17.0' \
  'IOS'

log "PASS: N11 real single-thread AsyncRT graph compiles for both iOS SDKs"
log "scope: compile/archive and dependency evidence only; N12 owns initialization and execution"
