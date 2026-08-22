#!/usr/bin/env bash
# Link the checked runtime-free archive through cc_import in a copied newer-rule
# app control. This never changes the root module graph or consumes an archive
# through a root Bazel target.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
archive_path="${MOJO_IOS_STATIC_ARCHIVE:-${repo_root}/bazel-bin/mojo/examples/ios/libmojo_ios_static_library_smoke.a}"
header_path="${MOJO_IOS_STATIC_HEADER:-${repo_root}/bazel-bin/mojo/examples/ios/mojo_ios_static_library_smoke.h}"
output_root="${MOJO_IOS_ARCHIVE_CONSUMER_OUT:-$(mktemp -d /tmp/mojo-ios-archive-consumer.XXXXXX)}"
trial_root="${output_root}/workspace"
user_root="${output_root}/bazel-user-root"
target="//app:trial_ios_application"

log() { printf '[mojo-ios-archive-consumer] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${bazel_bin}" >/dev/null 2>&1 || fail "BAZEL_BIN='${bazel_bin}' was not found"
[[ -f "${archive_path}" ]] || fail "archive does not exist: ${archive_path}"
[[ -f "${header_path}" ]] || fail "header does not exist: ${header_path}"
command -v vtool >/dev/null 2>&1 || fail 'vtool is required'
[[ ! -e "${trial_root}" ]] || fail "output workspace already exists: ${trial_root}"
mkdir -p "${trial_root}" "${user_root}"

log "validating source archive ${archive_path}"
archive_extract="$(mktemp -d /tmp/mojo-ios-archive-input.XXXXXX)"
(
  cd "${archive_extract}"
  ar -x "${archive_path}"
  vtool -show-build *.o | grep -q 'platform IOSSIMULATOR'
  nm -gU *.o | grep -Eq '(_?mojo_add)$'
)

cp -R "${script_dir}/." "${trial_root}/"
cp "${archive_path}" "${trial_root}/app/libmojo_ios_static_library_smoke.a"
cp "${header_path}" "${trial_root}/app/mojo_ios_static_library_smoke.h"
rm -f "${trial_root}/MODULE.bazel.lock"
perl -0pi -e 's/rules_apple", version = "4\.1\.0"/rules_apple", version = "4.5.3"/' "${trial_root}/MODULE.bazel"
perl -0pi -e 's/rules_swift",\n    version = "3\.1\.2"/rules_swift",\n    version = "3.5.0"/' "${trial_root}/MODULE.bazel"

run_bazel() {
  (cd "${trial_root}" && "${bazel_bin}" --output_user_root="${user_root}" --bazelrc=/dev/null "$@")
}

log "querying ${target}"
run_bazel query "${target}"
log "building archive-consumer compatibility control"
run_bazel build "${target}"

ipa_path="$(run_bazel cquery "${target}" --output=files | sed -nE '/\.ipa$/p' | tail -n 1)"
[[ -n "${ipa_path}" ]] || fail 'cquery did not report an IPA output'
[[ -f "${trial_root}/${ipa_path}" ]] || fail "reported IPA does not exist: ${ipa_path}"
log "PASS: isolated Simulator IPA linked the copied runtime-free archive: ${trial_root}/${ipa_path}"
log 'Scope: copied-artifact cc_import compatibility only; no root graph integration, Mojo runtime, external signing identity, installation, or execution claim.'
