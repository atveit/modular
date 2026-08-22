#!/usr/bin/env bash
# Report whether this checkout can declare a rules_apple/rules_swift iOS app.
# It makes no dependency changes and never launches a Simulator.  An optional
# Xcode link seam reuses the existing runtime-free Mojo static archive.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
bazel_bin="${BAZEL_BIN:-${repo_root}/bazelw}"
output_root="${MOJO_IOS_BAZEL_SWIFTUI_OUT:-/tmp/mojo-ios-bazel-swiftui-diagnostic}"

log() {
  printf '[mojo-ios-bazel-swiftui] %s\n' "$*"
}

command -v "${bazel_bin}" >/dev/null 2>&1 || {
  log "ERROR: BAZEL_BIN='${bazel_bin}' was not found" >&2
  exit 1
}

cd "${repo_root}"
log "Bazel: ${bazel_bin}"
"${bazel_bin}" query //mojo/examples/ios/swiftui_host:swiftui_host_fixture

missing_rules=0
for repo in rules_apple build_bazel_rules_swift; do
  query_log="${output_root}/${repo}.query.log"
  mkdir -p "${output_root}"
  if "${bazel_bin}" query "@${repo}//..." >"${query_log}" 2>&1; then
    log "repository visible: @${repo} (details: ${query_log})"
  else
    missing_rules=1
    log "repository unavailable: @${repo}"
    sed -n '1,6p' "${query_log}"
  fi
done

if [[ "${RUN_XCODE_LINK:-0}" == 1 ]]; then
  smoke_out="${output_root}/mojo-static"
  swift_out="${output_root}/swiftui-app"
  log "running existing Simulator-only Xcode archive/link seam (no launch)"
  MOJO_IOS_SMOKE_OUT="${smoke_out}" \
    "${repo_root}/mojo/examples/ios/run_simulator_smoke.sh"
  MOJO_IOS_ARCHIVE="${smoke_out}/libmojo_ios_smoke.a" \
    MOJO_IOS_SWIFT_LINK_OUT="${swift_out}" \
    "${script_dir}/link_swiftui_host.sh"
  log "PASS: Xcode seam reused ${smoke_out}/libmojo_ios_smoke.a"
fi

if (( missing_rules )); then
  log "SKIP: no rules_apple/rules_swift Bazel application target can be declared in this checkout."
  log "Next step: register compatible rule modules plus iOS platform/toolchain configuration, then add a Simulator ios_application backed by the existing SwiftUI sources and static-library provider."
  exit 0
fi

log "Rules repositories are visible, but this fixture intentionally declares no ios_application target yet."
log "No Bazel app build was attempted; verify platform/toolchain configuration before adding one."
