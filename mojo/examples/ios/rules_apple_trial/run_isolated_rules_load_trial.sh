#!/usr/bin/env bash
# Load the lockfile-selected Apple and Swift rule modules in a nested module.
# This diagnostic deliberately leaves the root MODULE.bazel graph untouched and
# does not declare, analyze, or build an ios_application.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
output_user_root="${MOJO_IOS_RULES_TRIAL_OUTPUT_USER_ROOT:-$(mktemp -d /tmp/mojo-ios-rules-load.XXXXXX)}"

log() { printf '[mojo-ios-rules-load] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${bazel_bin}" >/dev/null 2>&1 || fail "BAZEL_BIN='${bazel_bin}' was not found"

cd "${script_dir}"
log "Bazel: ${bazel_bin}"
log "isolated output user root: ${output_user_root}"
log 'querying the target whose BUILD file loads rules_apple and rules_swift public symbols'
"${bazel_bin}" --output_user_root="${output_user_root}" --bazelrc=/dev/null \
  query //:rules_loaded

graph_file="${output_user_root}/module-graph.json"
"${bazel_bin}" --output_user_root="${output_user_root}" --bazelrc=/dev/null \
  mod graph --output json >"${graph_file}"
grep -F '"name": "rules_apple"' "${graph_file}" >/dev/null || fail 'rules_apple was not selected'
grep -F '"version": "4.1.0"' "${graph_file}" >/dev/null || fail 'rules_apple 4.1.0 was not selected'
grep -F '"name": "rules_swift"' "${graph_file}" >/dev/null || fail 'rules_swift was not selected'
grep -F '"version": "3.1.2"' "${graph_file}" >/dev/null || fail 'rules_swift 3.1.2 was not selected'

log 'PASS: direct-dependency trial resolved and loaded rules_apple 4.1.0 and rules_swift 3.1.2'
log 'No ios_application was instantiated, analyzed, or built.'
