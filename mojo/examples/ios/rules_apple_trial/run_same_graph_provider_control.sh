#!/usr/bin/env bash
# Analyze a temporary Apple app whose cc_library directly consumes the local
# modular mojo_ios_static_library CcInfo provider. No root modules are edited.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
template_dir="${script_dir}/same_graph_provider_control"
output_root="${MOJO_IOS_SAME_GRAPH_OUT:-$(mktemp -d /tmp/mojo-ios-same-graph.XXXXXX)}"
trial_root="${output_root}/workspace"
user_root="${output_root}/bazel-user-root"
target="//:same_graph_ios_application"

log() { printf '[mojo-ios-same-graph] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${bazel_bin}" >/dev/null 2>&1 || fail "BAZEL_BIN='${bazel_bin}' was not found"
[[ ! -e "${trial_root}" ]] || fail "output workspace already exists: ${trial_root}"
mkdir -p "${trial_root}" "${user_root}"
cp -R "${template_dir}/." "${trial_root}/"
perl -0pi -e "s|__MODULAR_ROOT__|${repo_root}|g" "${trial_root}/MODULE.bazel.in"
mv "${trial_root}/MODULE.bazel.in" "${trial_root}/MODULE.bazel"

run_bazel() {
  (cd "${trial_root}" && "${bazel_bin}" --output_user_root="${user_root}" --bazelrc=/dev/null "$@")
}

log "temporary module: ${trial_root}"
log "local modular dependency: ${repo_root}"
log "querying ${target}"
query_log="${output_root}/same-graph-query.log"
if ! run_bazel query "${target}" >"${query_log}" 2>&1; then
  log "BLOCKED: same-graph module resolution failed; see ${query_log}"
  sed -n '1,120p' "${query_log}"
  exit 0
fi
log 'analyzing same-graph CcInfo consumer (--nobuild)'
analysis_log="${output_root}/same-graph-analysis.log"
if ! run_bazel build --nobuild "${target}" >"${analysis_log}" 2>&1; then
  log "BLOCKED: same-graph provider analysis failed; see ${analysis_log}"
  sed -n '1,160p' "${analysis_log}"
  exit 0
fi
log 'PASS: same-graph provider analysis completed'
log 'No app build/sign/install/run is attempted by this analysis control.'
