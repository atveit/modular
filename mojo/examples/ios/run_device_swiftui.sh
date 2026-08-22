#!/usr/bin/env bash
# Build, package, and optionally launch the visible SwiftUI Mojo hello app on
# an iOS device. This is command-line-only: no Xcode project or GUI is needed.
#
# Artifact-only mode:
#   mojo/examples/ios/run_device_swiftui.sh
#
# Signed device run:
#   IOS_DEVICE_RUN=1 \
#   IOS_DEVICE_ID=<UDID-or-name> \
#   IOS_CODE_SIGN_IDENTITY='Apple Development: ...' \
#   IOS_MOBILEPROVISION=/private/path/profile.mobileprovision \
#   mojo/examples/ios/run_device_swiftui.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_DEVICE_SWIFTUI_OUT:-${repo_root}/bazel-out/ios-mojo-swiftui-device}"
archive_root="${output_root}/mojo"
swift_root="${output_root}/swiftui"
bundle_id="${IOS_BUNDLE_ID:-com.modular.mojo.ios.smoke}"
device_id="${IOS_DEVICE_ID:-}"
signing_identity="${IOS_CODE_SIGN_IDENTITY:-}"
mobileprovision="${IOS_MOBILEPROVISION:-}"
entitlements="${IOS_ENTITLEMENTS:-}"

log() {
  printf '[ios-mojo-swiftui-device] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
command -v codesign >/dev/null 2>&1 || fail "codesign is required"

log "building Mojo device archive"
MOJO_IOS_TRIPLE="${MOJO_IOS_TRIPLE:-arm64-apple-ios17.0}" \
MOJO_IOS_SMOKE_OUT="${archive_root}" \
  "${script_dir}/run_simulator_smoke.sh"

log "linking SwiftUI host for device"
MOJO_IOS_SWIFT_TRIPLE="${MOJO_IOS_SWIFT_TRIPLE:-arm64-apple-ios17.0}" \
MOJO_IOS_ARCHIVE="${archive_root}/libmojo_ios_smoke.a" \
MOJO_IOS_SWIFT_LINK_OUT="${swift_root}" \
  "${script_dir}/swiftui_host/link_swiftui_host.sh"

app_path="${swift_root}/MojoIOSSmoke.app"
[[ -d "${app_path}" ]] || fail "SwiftUI app was not produced: ${app_path}"
if [[ "${bundle_id}" != "com.modular.mojo.ios.smoke" ]]; then
  plutil -replace CFBundleIdentifier -string "${bundle_id}" "${app_path}/Info.plist"
fi
log "unsigned/ad-hoc SwiftUI device app prepared: ${app_path}"

if [[ "${IOS_DEVICE_RUN:-0}" != 1 ]]; then
  log "PASS: SwiftUI device artifact/link preparation complete (set IOS_DEVICE_RUN=1 to sign/install/launch)"
  exit 0
fi

[[ -n "${device_id}" ]] || fail "IOS_DEVICE_ID is required when IOS_DEVICE_RUN=1"
[[ -n "${signing_identity}" ]] || fail "IOS_CODE_SIGN_IDENTITY is required when IOS_DEVICE_RUN=1"
[[ -n "${mobileprovision}" ]] || fail "IOS_MOBILEPROVISION is required when IOS_DEVICE_RUN=1"
[[ -f "${mobileprovision}" ]] || fail "provisioning profile not found: ${mobileprovision}"

cp "${mobileprovision}" "${app_path}/embedded.mobileprovision"
codesign_args=(--force --sign "${signing_identity}" --timestamp=none)
if [[ -n "${entitlements}" ]]; then
  [[ -f "${entitlements}" ]] || fail "entitlements file not found: ${entitlements}"
  codesign_args+=(--entitlements "${entitlements}")
fi
log "signing ${app_path}"
codesign "${codesign_args[@]}" "${app_path}"
codesign --verify --deep --strict "${app_path}"

log "installing on device ${device_id}"
xcrun devicectl device install app --device "${device_id}" "${app_path}"
log "launching ${bundle_id}"
xcrun devicectl device process launch --device "${device_id}" "${bundle_id}" --console
log "PASS: visible Mojo SwiftUI app installed and exited cleanly"
