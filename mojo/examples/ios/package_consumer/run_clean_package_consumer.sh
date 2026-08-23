#!/bin/bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_root="$(cd "${script_dir}/../../../.." && pwd)"
readonly output_root="${MOJO_IOS_PACKAGE_OUT:-/tmp/mojo-ios-package-consumer}"
readonly jobs="${MOJO_IOS_BAZEL_JOBS:-16}"
readonly simulator_device="${MOJO_IOS_SIMULATOR_DEVICE:-iPhone 17 Pro}"
readonly mojo_target="//mojo/examples/ios:mojo_ios_archive"
readonly core_target="//mojo/examples/ios:compilerrt_ios_core"
readonly bridge_target="//mojo/examples/ios/package_consumer:mojo_ios_package_bridge"
readonly bundle_id="com.modular.mojo.ios.package-consumer"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: N10 packaging requires Xcode on macOS"
  exit 0
fi
if [[ -e "${output_root}" ]]; then
  fail "output already exists: ${output_root}"
fi
for tool in ar codesign ditto nm plutil vtool xcodebuild xcrun; do
  command -v "${tool}" >/dev/null 2>&1 || fail "missing required tool: ${tool}"
done

mkdir -p "${output_root}/slices" "${output_root}/headers"

check_archive() {
  local archive="$1"
  local expected_platform="$2"
  local extract_dir="$3"
  mkdir -p "${extract_dir}"
  (
    cd "${extract_dir}"
    ar -x "${archive}"
  )

  local found=0
  while IFS= read -r object; do
    found=1
    local metadata
    metadata="$(vtool -show-build "${object}")"
    grep -Eq "platform[[:space:]]+${expected_platform}$" <<<"${metadata}"
    grep -Eq 'minos[[:space:]]+17\.0$' <<<"${metadata}"
  done < <(find "${extract_dir}" -type f -name '*.o' -print)
  [[ "${found}" == 1 ]] || fail "no objects in ${archive}"

  for symbol in \
    mojo_ios_package_add \
    mojo_ios_package_hello_utf8 \
    mojo_add \
    mojo_hello_utf8 \
    KGEN_CompilerRT_Initialize; do
    count="$(nm -gU "${archive}" | awk -v symbol="_${symbol}" '$NF == symbol { count++ } END { print count + 0 }')"
    [[ "${count}" == 1 ]] || fail "expected exactly one ${symbol} in ${archive}, found ${count}"
  done
  if nm -gU "${archive}" | grep -Eq 'KGEN_CompilerRT_AsyncRT_|Python|JIT|Tracy|TCMalloc'; then
    fail "forbidden runtime family entered ${archive}"
  fi
}

build_slice() {
  local platform_label="$1"
  local sdk="$2"
  local expected_platform="$3"
  local slice_name="$4"
  local slice_root="${output_root}/slices/${slice_name}"
  mkdir -p "${slice_root}"

  "${repo_root}/bazelw" build \
    --config=build-mojo \
    --jobs="${jobs}" \
    --features= \
    --platforms="${platform_label}" \
    "${mojo_target}" \
    "${core_target}" \
    "${bridge_target}"

  cp "${repo_root}/bazel-bin/mojo/examples/ios/libmojo_ios_archive.a" \
    "${slice_root}/libmojo.a"
  cp "${repo_root}/bazel-bin/mojo/examples/ios/libcompilerrt_ios_core.a" \
    "${slice_root}/libcore.a"
  cp "${repo_root}/bazel-bin/mojo/examples/ios/package_consumer/libmojo_ios_package_bridge.a" \
    "${slice_root}/libbridge.a"

  ZERO_AR_DATE=1 xcrun --sdk "${sdk}" libtool -static \
    -o "${slice_root}/libMojoIOSCore.a" \
    "${slice_root}/libbridge.a" \
    "${slice_root}/libmojo.a" \
    "${slice_root}/libcore.a"
  check_archive \
    "${slice_root}/libMojoIOSCore.a" \
    "${expected_platform}" \
    "${slice_root}/objects"
}

cd "${repo_root}"
build_slice \
  "@build_bazel_apple_support//platforms:ios_sim_arm64" \
  iphonesimulator \
  IOSSIMULATOR \
  simulator
build_slice \
  "@build_bazel_apple_support//platforms:ios_arm64" \
  iphoneos \
  IOS \
  device

cp "${script_dir}/MojoIOSCore.h" "${output_root}/headers/"
cp "${script_dir}/module.modulemap" "${output_root}/headers/"
readonly xcframework="${output_root}/MojoIOSCore.xcframework"
xcodebuild -create-xcframework \
  -library "${output_root}/slices/device/libMojoIOSCore.a" \
  -headers "${output_root}/headers" \
  -library "${output_root}/slices/simulator/libMojoIOSCore.a" \
  -headers "${output_root}/headers" \
  -output "${xcframework}"

readonly manifest="${xcframework}/Info.plist"
test -s "${manifest}"
manifest_text="$(plutil -p "${manifest}")"
grep -Fq '"LibraryIdentifier" => "ios-arm64"' <<<"${manifest_text}"
grep -Fq '"LibraryIdentifier" => "ios-arm64-simulator"' <<<"${manifest_text}"
[[ "$(find "${xcframework}" -type f -name libMojoIOSCore.a | wc -l | tr -d ' ')" == 2 ]]

# Copy only the package sources and the completed XCFramework into a clean
# directory. From this point on no Bazel or Mojo compiler command is invoked.
readonly clean_root="${output_root}/clean-package"
mkdir -p "${clean_root}/Artifacts"
cp "${script_dir}/Package.swift" "${clean_root}/"
ditto "${script_dir}/Sources" "${clean_root}/Sources"
ditto "${xcframework}" "${clean_root}/Artifacts/MojoIOSCore.xcframework"

readonly simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
readonly swift_log="${output_root}/swift-build.log"
readonly scratch_path="${clean_root}/.build"
env -i \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/swift package \
    --package-path "${clean_root}" describe --type json \
    >"${output_root}/package-description.json"
env -i \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/swift build \
    --package-path "${clean_root}" \
    --scratch-path "${scratch_path}" \
    --sdk "${simulator_sdk}" \
    --triple arm64-apple-ios17.0-simulator \
    --product MojoIOSCleanConsumer \
    -v >"${swift_log}" 2>&1

if grep -Fq "${repo_root}" "${swift_log}"; then
  fail "clean consumer build referenced the source repository"
fi
if grep -Eq '(^|[ /])(mojo-full|mojo build)([ /]|$)' "${swift_log}"; then
  fail "clean consumer build invoked a Mojo compiler"
fi

readonly executable="$(find "${scratch_path}" -type f -name MojoIOSCleanConsumer -perm +111 -print | head -1)"
[[ -n "${executable}" ]] || fail "Swift Package executable was not produced"
metadata="$(vtool -show-build "${executable}")"
grep -Eq 'platform[[:space:]]+IOSSIMULATOR$' <<<"${metadata}"
grep -Eq 'minos[[:space:]]+17\.0$' <<<"${metadata}"
for symbol in mojo_ios_package_add mojo_ios_package_hello_utf8 KGEN_CompilerRT_Initialize; do
  count="$(nm "${executable}" | awk -v symbol="_${symbol}" '$NF == symbol { count++ } END { print count + 0 }')"
  [[ "${count}" == 1 ]] || fail "expected exactly one ${symbol} in clean executable, found ${count}"
done

readonly app="${output_root}/MojoIOSCleanConsumer.app"
mkdir -p "${app}"
cp "${executable}" "${app}/MojoIOSCleanConsumer"
cp "${script_dir}/Info.plist" "${app}/Info.plist"
codesign --force --sign - "${app}" >/dev/null
codesign --verify --deep --strict "${app}"

simulator_udid="$(
  xcrun simctl list devices available |
    sed -n "s/^[[:space:]]*${simulator_device} (\([0-9A-F-]*\)).*/\1/p" |
    head -1
)"
[[ -n "${simulator_udid}" ]] || fail "no available ${simulator_device} Simulator"
xcrun simctl boot "${simulator_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${simulator_udid}" -b
xcrun simctl install "${simulator_udid}" "${app}"
readonly data_container="$(xcrun simctl get_app_container "${simulator_udid}" "${bundle_id}" data)"
readonly marker="${data_container}/Documents/mojo-ios-package-pass.txt"
xcrun simctl terminate "${simulator_udid}" "${bundle_id}" 2>/dev/null || true
rm -f "${marker}"
xcrun simctl launch "${simulator_udid}" "${bundle_id}"
for _ in {1..20}; do
  [[ -f "${marker}" ]] && break
  sleep 0.5
done
grep -Fxq 'MOJO_IOS_PACKAGE_PASS' "${marker}" || fail "clean app runtime marker is missing"

readonly screenshot="${output_root}/MojoIOSCleanConsumer.png"
sleep 2
xcrun simctl io "${simulator_udid}" screenshot "${screenshot}"

echo "PASS: N10 XCFramework and clean Swift Package consumer"
echo "XCFramework: ${xcframework}"
echo "Clean package: ${clean_root}"
echo "App: ${app}"
echo "Runtime marker: ${marker}"
echo "Screenshot: ${screenshot}"
shasum -a 256 "${xcframework}/Info.plist" "${screenshot}"
