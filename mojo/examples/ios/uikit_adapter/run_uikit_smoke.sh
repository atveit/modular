#!/usr/bin/env bash
# Objective-C UIKit adapter coverage. Default checks both arm64 iOS slices;
# RUN_SIMULATOR=1 additionally launches only the Simulator app.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift_bin="${SWIFT_BIN:-swiftc}"
output_root="${MOJO_IOS_UIKIT_OUT:-/tmp/mojo-ios-uikit-probe}"
app_id="com.modular.mojo.ios.uikit"

log() { printf '[mojo-ios-uikit] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v "${swift_bin}" >/dev/null 2>&1 || fail "SWIFT_BIN='${swift_bin}' was not found"
command -v xcrun >/dev/null 2>&1 || fail 'xcrun is required'
command -v vtool >/dev/null 2>&1 || fail 'vtool is required for Mach-O verification'

mkdir -p "${output_root}"
simulator_executable=""
for target_triple in arm64-apple-ios17.0 arm64-apple-ios17.0-simulator; do
  case "${target_triple}" in
    *-simulator)
      sdk_name="iphonesimulator"
      minimum_os_flag="-mios-simulator-version-min=17.0"
      expected_platform="IOSSIMULATOR"
      slice_name="simulator"
      ;;
    *)
      sdk_name="iphoneos"
      minimum_os_flag="-miphoneos-version-min=17.0"
      expected_platform="IOS"
      slice_name="device"
      ;;
  esac

  slice_root="${output_root}/${slice_name}"
  adapter_object="${slice_root}/mojo_ios_uikit.o"
  executable_path="${slice_root}/uikit_consumer"
  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  clang_bin="$(xcrun --sdk "${sdk_name}" --find clang)"
  mkdir -p "${slice_root}/module-cache"

  log "compiling Objective-C UIKit adapter for ${target_triple}"
  "${clang_bin}" -target "${target_triple}" -isysroot "${sdk_path}" \
    "${minimum_os_flag}" -arch arm64 -fobjc-arc -I"${script_dir}" \
    -c "${script_dir}/mojo_ios_uikit.m" -o "${adapter_object}"

  log "linking Swift consumer and UIKit.framework for ${slice_name}"
  SDKROOT="${sdk_path}" "${swift_bin}" -parse-as-library -target "${target_triple}" \
    -sdk "${sdk_path}" -module-cache-path "${slice_root}/module-cache" \
    -Xcc "-fmodule-map-file=${script_dir}/MojoIOSUIKit.modulemap" \
    "${script_dir}/UIKitConsumer.swift" "${adapter_object}" \
    -framework UIKit -o "${executable_path}"

  file "${adapter_object}" "${executable_path}"
  nm -gU "${adapter_object}" | grep -E '(_?mojo_uikit_main_screen_scale)$'
  nm -gU "${executable_path}" | grep -E '(_?mojo_uikit_main_screen_scale)$'
  nm -u "${adapter_object}" | grep -F '_OBJC_CLASS_$_UIScreen'
  nm -u "${executable_path}" | grep -F '_OBJC_CLASS_$_UIScreen'
  build_info="$(vtool -show-build "${executable_path}")"
  printf '%s\n' "${build_info}" | sed -n '1,100p'
  printf '%s\n' "${build_info}" | grep -q "platform ${expected_platform}" || fail "wrong platform for ${slice_name}"
  otool -L "${executable_path}" | grep -F 'UIKit.framework/UIKit'
  log "PASS: ${slice_name} Objective-C UIKit compile/link metadata"

  if [[ "${slice_name}" == simulator ]]; then
    simulator_executable="${executable_path}"
  fi
done

if [[ "${RUN_SIMULATOR:-0}" != 1 ]]; then
  log 'compile/link-only evidence (set RUN_SIMULATOR=1 for the UIKit screen-scale Simulator marker)'
  exit 0
fi

if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  log 'SKIP: CoreSimulator is unavailable'
  exit 0
fi
device_udid="${SIMULATOR_UDID:-}"
if [[ -z "${device_udid}" ]]; then
  device_udid="$(xcrun simctl list devices available | sed -nE '/iPhone.*\([0-9A-F-]{36}\)/ { s/.*\(([0-9A-F-]{36})\).*/\1/p; q; }')"
fi
[[ -n "${device_udid}" ]] || { log 'SKIP: no available iPhone Simulator device'; exit 0; }

app_path="${output_root}/UIKitConsumer.app"
launch_log="${output_root}/uikit-launch.log"
log 'packaging and ad-hoc signing Simulator app'
mkdir -p "${app_path}"
cp "${script_dir}/../Info.plist" "${app_path}/Info.plist"
cp "${simulator_executable}" "${app_path}/mojo_ios_smoke"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${app_id}" "${app_path}/Info.plist"
codesign --force --sign - "${app_path}" >/dev/null
codesign --verify --deep --strict "${app_path}"

log "booting ${device_udid}"
xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b
log "installing ${app_path}"
xcrun simctl install "${device_udid}" "${app_path}"
log 'launching UIKit screen-scale runtime check'
xcrun simctl launch --console "${device_udid}" "${app_id}" | tee "${launch_log}"
grep -qx 'MOJO_UIKIT_SCREEN_SCALE_PASS' "${launch_log}" || fail 'UIKit screen-scale runtime marker was not observed'
log 'PASS: UIKit scalar adapter completed on iOS Simulator'
log 'This is UIKit adapter runtime evidence only; it is not Mojo runtime or physical-device evidence.'
