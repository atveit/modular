#!/usr/bin/env bash
# Build the minimal Apple/Swift app with a newer rule pair in a copied nested
# module. This never edits the repository root MODULE.bazel or lockfile.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
output_root="${MOJO_IOS_RULES_COMPAT_OUT:-$(mktemp -d /tmp/mojo-ios-rules-compat.XXXXXX)}"
trial_root="${output_root}/workspace"
user_root="${output_root}/bazel-user-root"
target="//app:trial_ios_application"

log() {
  printf '[mojo-ios-rules-compat] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${bazel_bin}" >/dev/null 2>&1 || fail "BAZEL_BIN='${bazel_bin}' was not found"
[[ ! -e "${trial_root}" ]] || fail "output workspace already exists: ${trial_root}"
mkdir -p "${trial_root}" "${user_root}"
cp -R "${script_dir}/." "${trial_root}/"

# The copied lockfile represents 4.1.0/3.1.2. Let the temporary module resolve
# its own lock after the explicit version substitutions below.
rm -f "${trial_root}/MODULE.bazel.lock"
perl -0pi -e 's/rules_apple", version = "4\.1\.0"/rules_apple", version = "4.5.3"/' \
  "${trial_root}/MODULE.bazel"
perl -0pi -e 's/rules_swift",\n    version = "3\.1\.2"/rules_swift",\n    version = "3.5.0"/' \
  "${trial_root}/MODULE.bazel"
grep -q 'rules_apple", version = "4.5.3"' "${trial_root}/MODULE.bazel" || fail "rules_apple version substitution failed"
grep -q 'version = "3.5.0"' "${trial_root}/MODULE.bazel" || fail "rules_swift version substitution failed"

run_bazel() {
  (cd "${trial_root}" && "${bazel_bin}" --output_user_root="${user_root}" --bazelrc=/dev/null "$@")
}

log "temporary nested module: ${trial_root}"
log "Bazel: ${bazel_bin}"
log "rule control: rules_apple 4.5.3, rules_swift 3.5.0"
log "graph note: rules_swift 3.5.0 requires protobuf 34.0.bcr.1; root currently selects 33.5"
log "querying ${target}"
run_bazel query "${target}"
log "analyzing ${target} (--nobuild)"
run_bazel build --nobuild "${target}"
log "building ${target}"
run_bazel build "${target}"

ipa_path="$(run_bazel cquery "${target}" --output=files | sed -nE '/\.ipa$/p' | tail -n 1)"
[[ -n "${ipa_path}" ]] || fail "cquery did not report an IPA output"
[[ -f "${trial_root}/${ipa_path}" ]] || fail "reported IPA does not exist: ${ipa_path}"
log "PASS: isolated Simulator IPA build: ${trial_root}/${ipa_path}"
log "This is rule/toolchain compatibility evidence only; no Mojo archive, runtime, signing, installation, or execution is claimed."
