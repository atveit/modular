#!/usr/bin/env bash
# Validate the generic Xcode SDK repository rule in a temporary module. This
# does not register an Apple toolchain or change the root module graph.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
output_root="${APPLE_SYSROOT_DIAGNOSTIC_OUT:-$(mktemp -d /tmp/apple-sysroot-repository-diagnostic.XXXXXX)}"

log() { printf '[apple-sysroot-diagnostic] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${bazel_bin}" >/dev/null 2>&1 || fail "BAZEL_BIN='${bazel_bin}' was not found"
command -v xcrun >/dev/null 2>&1 || fail 'xcrun is required'
[[ -f "${script_dir}/apple_sysroot_repository.bzl" ]] || fail 'generic repository rule is missing'

run_sdk() {
  local sdk_name="$1"
  local workspace="${output_root}/${sdk_name}"
  local user_root="${workspace}/bazel-user-root"

  mkdir -p "${workspace}"
  cp "${script_dir}/apple_sysroot_repository.bzl" "${workspace}/apple_sysroot_repository.bzl"
  cp "${script_dir}/apple_sysroot_repository_diagnostic/BUILD.bazel" "${workspace}/BUILD.bazel"
  cp "${script_dir}/apple_sysroot_repository_diagnostic/MODULE.bazel.in" "${workspace}/MODULE.bazel"
  perl -0pi -e "s|__SDK_NAME__|${sdk_name}|g" "${workspace}/MODULE.bazel"

  log "querying ${sdk_name} SDK repository targets"
  (
    cd "${workspace}"
    "${bazel_bin}" --output_user_root="${user_root}" --bazelrc=/dev/null query @apple-sdk-diagnostic//sysroot:root
    "${bazel_bin}" --output_user_root="${user_root}" --bazelrc=/dev/null query @apple-sdk-diagnostic//sysroot:directory
  )
  log "PASS: ${sdk_name} SDK repository exposes its allowlisted sysroot targets"
}

run_sdk iphonesimulator
run_sdk iphoneos
log 'Scope: repository-rule discovery only; no root registration, CC toolchain selection, app build, signing, or execution.'
