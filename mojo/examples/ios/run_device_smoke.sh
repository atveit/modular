#!/usr/bin/env bash
# Build the runtime-free Mojo iOS device fixture and, when explicitly enabled,
# sign/install/launch it on a development device.
#
# Artifact-only mode is safe for CI and does not require signing material:
#   mojo/examples/ios/run_device_smoke.sh
#
# A real-device run requires a matching development provisioning profile and
# identity. Keep those paths and identifiers outside the repository:
#   IOS_DEVICE_RUN=1 \
#   IOS_DEVICE_ID=<UDID-or-name> \
#   IOS_CODE_SIGN_IDENTITY='Apple Development: ...' \
#   IOS_MOBILEPROVISION=/private/path/profile.mobileprovision \
#   mojo/examples/ios/run_device_smoke.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
output_root="${MOJO_IOS_DEVICE_OUT:-${repo_root}/bazel-out/ios-mojo-smoke-device}"
bundle_id="${IOS_BUNDLE_ID:-com.modular.mojo.ios.smoke}"
device_id="${IOS_DEVICE_ID:-}"
signing_identity="${IOS_CODE_SIGN_IDENTITY:-}"
mobileprovision="${IOS_MOBILEPROVISION:-}"
entitlements="${IOS_ENTITLEMENTS:-}"

log() {
  printf '[ios-mojo-device] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"
command -v codesign >/dev/null 2>&1 || fail "codesign is required"

log "building device object/archive/link probe"
MOJO_IOS_TRIPLE="${MOJO_IOS_TRIPLE:-arm64-apple-ios17.0}" \
MOJO_IOS_SMOKE_OUT="${output_root}" \
  "${script_dir}/run_simulator_smoke.sh"

device_executable="${output_root}/mojo_ios_smoke_device"
[[ -f "${device_executable}" ]] || fail "device executable was not produced: ${device_executable}"

app_path="${output_root}/mojo_ios_smoke.app"
rm -rf "${app_path}"
mkdir -p "${app_path}"
cp "${script_dir}/Info.plist" "${app_path}/Info.plist"
cp "${device_executable}" "${app_path}/mojo_ios_smoke"
if [[ "${bundle_id}" != "com.modular.mojo.ios.smoke" ]]; then
  plutil -replace CFBundleIdentifier -string "${bundle_id}" "${app_path}/Info.plist"
fi

file "${app_path}/mojo_ios_smoke"
log "unsigned device app prepared: ${app_path}"

if [[ "${IOS_DEVICE_RUN:-0}" != 1 ]]; then
  log "PASS: device artifact/app preparation complete (set IOS_DEVICE_RUN=1 to sign/install/launch)"
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
log "PASS: Mojo device app installed and exited cleanly"
