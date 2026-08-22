#!/usr/bin/env bash
# Analyze and attempt to build the isolated rules_apple iOS application.
# It never changes the root module graph and has no Mojo archive dependency.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
output_user_root="${MOJO_IOS_APP_TRIAL_OUTPUT_USER_ROOT:-$(mktemp -d /tmp/mojo-ios-app-trial.XXXXXX)}"
target='//app:trial_ios_application'

log() { printf '[mojo-ios-app-trial] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${bazel_bin}" >/dev/null 2>&1 || fail "BAZEL_BIN='${bazel_bin}' was not found"
mkdir -p "${output_user_root}"
cd "${script_dir}"

run_bazel() {
  "${bazel_bin}" --output_user_root="${output_user_root}" --bazelrc=/dev/null "$@"
}

log "Bazel: ${bazel_bin}"
log "isolated output user root: ${output_user_root}"
log "querying ${target}"
run_bazel query "${target}"

analysis_log="${output_user_root}/ios-application-analysis.log"
log 'analyzing isolated ios_application (--nobuild)'
if ! run_bazel build --nobuild "${target}" >"${analysis_log}" 2>&1; then
  log "BLOCKED: isolated ios_application analysis failed; see ${analysis_log}"
  sed -n '1,120p' "${analysis_log}"
  exit 0
fi
log 'PASS: isolated ios_application analyzed'

build_log="${output_user_root}/ios-application-build.log"
log 'building isolated ios_application'
if ! run_bazel build "${target}" >"${build_log}" 2>&1; then
  log "BLOCKED: isolated ios_application build failed; see ${build_log}"
  sed -n '1,160p' "${build_log}"
  exit 0
fi

log 'PASS: isolated ios_application built'
log 'No Mojo archive was linked, and this script does not sign, install, or run an app.'
