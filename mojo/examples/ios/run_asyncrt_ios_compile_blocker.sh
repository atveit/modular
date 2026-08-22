#!/usr/bin/env bash
# Record the current AsyncRT iOS SDK compile blocker. This is a discovery-only
# diagnostic: it never archives, links, packages, or executes AsyncRT.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
bazel_wrapper="${repo_root}/bazelw"
output_root="${MOJO_IOS_ASYNCRT_COMPILE_BLOCKER_OUT:-${repo_root}/bazel-out/ios-asyncrt-compile-blocker}"

log() { printf '[ios-asyncrt-compile-blocker] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
[[ -x "${bazel_wrapper}" ]] || fail "bazelw is required"
mkdir -p "${output_root}"

# This host build materializes the repository LLVM source/generated headers.
# Its archive and any host LLVM libraries are never compile/link inputs here.
"${bazel_wrapper}" build --config=build-mojo //KGEN:CompilerRTIOSStatic
exec_root="$("${bazel_wrapper}" info --config=build-mojo execution_root)"
bazel_bin="$("${bazel_wrapper}" info --config=build-mojo bazel-bin)"
llvm_source_include="${exec_root}/external/+llvm_configure+llvm-project/llvm/include"
llvm_generated_include="${bazel_bin}/external/+llvm_configure+llvm-project/llvm/include"
[[ -d "${llvm_source_include}" && -d "${llvm_generated_include}" ]] || fail "missing Bazel LLVM headers"

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
clangxx_bin="$(xcrun --sdk iphonesimulator --find clang++)"
compile_log="${output_root}/AsyncRT.compile.log"
object_path="${output_root}/AsyncRT.o"

log "compiling KGEN/lib/CompilerRT/AsyncRT.cpp for arm64 iOS Simulator"
set +e
"${clangxx_bin}" -target arm64-apple-ios17.0-simulator -isysroot "${sdk_path}" \
  -mios-simulator-version-min=17.0 -arch arm64 -std=c++20 \
  -DMODULAR_BUILDING_COMPILERRT -I"${repo_root}/AsyncRT/include" \
  -I"${repo_root}/Support/include" -I"${repo_root}/KGEN/include" \
  -isystem "${llvm_source_include}" -isystem "${llvm_generated_include}" \
  -c "${repo_root}/KGEN/lib/CompilerRT/AsyncRT.cpp" -o "${object_path}" \
  >"${compile_log}" 2>&1
compile_status=$?
set -e
cat "${compile_log}"

if [[ "${compile_status}" -eq 0 ]]; then
  fail "AsyncRT.cpp unexpectedly compiled; update this discovery gate before drawing conclusions"
fi
if ! grep -Eq "getSize|EnvPathSeparator|mlir/Support/LLVM.h.*file not found" "${compile_log}"; then
  fail "compile failed without the expected target-configured LLVM/MLIR boundary: ${compile_log}"
fi
log "BLOCKED: iOS target-configured LLVM/MLIR header/toolchain contract is absent"
log "No AsyncRT object/archive/link/run or runtime-support claim was produced."
