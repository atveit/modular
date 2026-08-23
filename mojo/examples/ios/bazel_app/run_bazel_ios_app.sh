#!/bin/bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd "${script_dir}/../../../.." && pwd)"
readonly jobs="${MOJO_IOS_BAZEL_JOBS:-16}"
readonly simulator_device="${MOJO_IOS_SIMULATOR_DEVICE:-iPhone 17 Pro}"
readonly app_target="//mojo/examples/ios/bazel_app:MojoIOSApp"
readonly unit_target="//mojo/examples/ios/bazel_app:MojoIOSAppTests"
readonly ui_target="//mojo/examples/ios/bazel_app:MojoIOSAppUITests"
readonly platform="@build_bazel_apple_support//platforms:ios_sim_arm64"
readonly bundle_id="com.modular.mojo.ios.bazel"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: the canonical iOS app requires Xcode on macOS"
  exit 0
fi

simulator_version="${MOJO_IOS_SIMULATOR_VERSION:-}"
if [[ -z "${simulator_version}" ]]; then
  simulator_version="$(xcrun simctl list runtimes | awk '/^iOS / { print $2; exit }')"
fi
if [[ -z "${simulator_version}" ]]; then
  echo "FAIL: no installed iOS Simulator runtime" >&2
  exit 1
fi

bazel_args=(
  --config=build-mojo
  --jobs="${jobs}"
  --features=
  --platforms="${platform}"
  "--@build_bazel_rules_apple//apple/build_settings:ios_simulator_device=${simulator_device}"
  "--@build_bazel_rules_apple//apple/build_settings:ios_simulator_version=${simulator_version}"
)

cd "${repo_root}"
"${repo_root}/bazelw" test "${bazel_args[@]}" \
  "${unit_target}" \
  --nocache_test_results \
  --test_output=errors
"${repo_root}/bazelw" test "${bazel_args[@]}" \
  "${ui_target}" \
  --nocache_test_results \
  --test_output=errors

# Build last so bazel-bin points at the app configuration rather than a test
# runner configuration when output path stripping is active.
"${repo_root}/bazelw" build "${bazel_args[@]}" "${app_target}"

readonly ipa="${repo_root}/bazel-bin/mojo/examples/ios/bazel_app/MojoIOSApp.ipa"
test -s "${ipa}"
readonly work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mojo-ios-bazel-app.XXXXXX")"
trap 'rm -r "${work_dir}"' EXIT
ditto -x -k "${ipa}" "${work_dir}"
readonly app="${work_dir}/Payload/MojoIOSApp.app"
readonly executable="${app}/MojoIOSApp"
test -s "${executable}"

metadata="$(vtool -show-build "${executable}")"
grep -Eq 'platform[[:space:]]+IOSSIMULATOR$' <<<"${metadata}"
grep -Eq 'minos[[:space:]]+17\.0$' <<<"${metadata}"
nm -gU "${executable}" | grep -Eq '(_?mojo_add)$'
nm -gU "${executable}" | grep -Eq '(_?mojo_hello_utf8)$'
nm "${executable}" | grep -Eq '(_?KGEN_CompilerRT_Initialize)$'
codesign --verify --deep --strict "${app}"

link_action="${work_dir}/objc-link-action.txt"
"${repo_root}/bazelw" aquery "${bazel_args[@]}" \
  "mnemonic(ObjcLink, ${app_target})" \
  --output=text >"${link_action}"
grep -Fq 'libmojo_ios_archive.a' "${link_action}"
grep -Fq -- '--target=arm64-apple-ios17.0-simulator' "${link_action}"
if grep -Fq -- '-fuse-ld=lld' "${link_action}"; then
  echo "FAIL: Swift app link selected the non-Apple linker" >&2
  exit 1
fi

simulator_udid="$(
  xcrun simctl list devices available |
    sed -n "s/^[[:space:]]*${simulator_device} (\([0-9A-F-]*\)).*/\1/p" |
    head -1
)"
if [[ -z "${simulator_udid}" ]]; then
  echo "FAIL: no available '${simulator_device}' Simulator" >&2
  exit 1
fi
xcrun simctl boot "${simulator_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${simulator_udid}" -b
xcrun simctl install "${simulator_udid}" "${app}"
xcrun simctl launch "${simulator_udid}" "${bundle_id}"
sleep 2

readonly evidence_dir="${repo_root}/bazel-out/ios-bazel-app"
mkdir -p "${evidence_dir}"
readonly screenshot="${evidence_dir}/MojoIOSApp.png"
xcrun simctl io "${simulator_udid}" screenshot "${screenshot}"

echo "PASS: Bazel SwiftUI app, XCTest, XCUITest, install, and launch"
echo "Simulator: ${simulator_device} / iOS ${simulator_version} / ${simulator_udid}"
echo "IPA: ${ipa}"
echo "Screenshot: ${screenshot}"
shasum -a 256 "${screenshot}"
