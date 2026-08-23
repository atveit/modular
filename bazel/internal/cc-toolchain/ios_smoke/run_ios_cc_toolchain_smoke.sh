#!/bin/bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd "${script_dir}/../../../.." && pwd)"
readonly target="//bazel/internal/cc-toolchain/ios_smoke:ios_cc_toolchain_smoke"
readonly jobs="${MOJO_IOS_BAZEL_JOBS:-16}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: the iOS C++ toolchain smoke requires Xcode on macOS"
  exit 0
fi

check_platform() {
  local platform_label="$1"
  local expected_platform="$2"
  local expected_target="$3"
  local expected_sysroot="$4"

  "${repo_root}/bazelw" build \
    --config=prebuilt-mojo \
    --jobs="${jobs}" \
    --platforms="${platform_label}" \
    "${target}"

  local binary="${repo_root}/bazel-bin/bazel/internal/cc-toolchain/ios_smoke/ios_cc_toolchain_smoke"
  local metadata
  metadata="$(vtool -show-build "${binary}")"
  grep -Eq "platform[[:space:]]+${expected_platform}$" <<<"${metadata}"
  grep -Eq "minos[[:space:]]+17\.0$" <<<"${metadata}"

  local action
  action="$(
    "${repo_root}/bazelw" aquery \
      --config=prebuilt-mojo \
      --platforms="${platform_label}" \
      "mnemonic(CppCompile, ${target})" \
      --output=text
  )"
  grep -Fq -- "--target=${expected_target}" <<<"${action}"
  grep -Fq -- "--sysroot=external/+apple_sysroot_repository+${expected_sysroot}/sysroot" <<<"${action}"
  if grep -Fq xcrun <<<"${action}"; then
    echo "FAIL: xcrun leaked into an iOS compile action" >&2
    exit 1
  fi

  echo "PASS: ${expected_platform} target=${expected_target} minos=17.0"
}

cd "${repo_root}"
check_platform \
  "@build_bazel_apple_support//platforms:ios_sim_arm64" \
  "IOSSIMULATOR" \
  "arm64-apple-ios17.0-simulator" \
  "sysroot-ios-simulator"
check_platform \
  "@build_bazel_apple_support//platforms:ios_arm64" \
  "IOS" \
  "arm64-apple-ios17.0" \
  "sysroot-ios-device"
