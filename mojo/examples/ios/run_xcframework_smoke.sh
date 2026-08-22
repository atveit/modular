#!/usr/bin/env bash
# Package the runtime-free Mojo C ABI fixture as a dual-slice XCFramework.
#
# This is an artifact-only packaging smoke test. It creates device and
# Simulator archives, verifies their Mach-O metadata, and calls
# xcodebuild -create-xcframework. It neither needs a signing identity nor
# installs or runs an application on a physical device.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="${MOJO_IOS_XCFRAMEWORK_OUT:-/tmp/mojo-ios-xcframework-smoke}"
simulator_root="${output_root}/simulator"
device_root="${output_root}/device"
headers_root="${output_root}/headers"
xcframework_path="${output_root}/MojoIOSSmoke.xcframework"
package_root="${output_root}/SwiftPackage"
framework_name='MojoIOSSmoke'

log() { printf '[mojo-ios-xcframework] %s\n' "$*"; }
fail() {
  log "ERROR: $*" >&2
  exit 1
}

command -v xcodebuild >/dev/null 2>&1 || fail 'xcodebuild is required'
command -v xcrun >/dev/null 2>&1 || fail 'xcrun is required'
command -v ar >/dev/null 2>&1 || fail 'ar is required'
command -v swift >/dev/null 2>&1 || fail 'swift is required'
[[ -f "${script_dir}/mojo_ios_smoke.h" ]] || fail 'fixture header is missing'
[[ ! -e "${xcframework_path}" ]] || fail "output already exists: ${xcframework_path}; choose a new MOJO_IOS_XCFRAMEWORK_OUT"

mkdir -p "${output_root}" "${headers_root}"
cp "${script_dir}/mojo_ios_smoke.h" "${headers_root}/mojo_ios_smoke.h"
cat >"${headers_root}/module.modulemap" <<'EOF'
module MojoIOSSmoke {
  header "mojo_ios_smoke.h"
  export *
}
EOF

log 'building artifact-only Simulator archive'
MOJO_IOS_TRIPLE='arm64-apple-ios17.0-simulator' \
MOJO_IOS_SMOKE_OUT="${simulator_root}" \
  "${script_dir}/run_simulator_smoke.sh"

log 'building artifact-only device archive (no signing/install)'
MOJO_IOS_TRIPLE='arm64-apple-ios17.0' \
MOJO_IOS_SMOKE_OUT="${device_root}" \
  "${script_dir}/run_simulator_smoke.sh"

simulator_archive="${simulator_root}/libmojo_ios_smoke.a"
device_archive="${device_root}/libmojo_ios_smoke.a"
for archive_path in "${simulator_archive}" "${device_archive}"; do
  [[ -f "${archive_path}" ]] || fail "archive was not produced: ${archive_path}"
  ar -t "${archive_path}" | grep -qx 'mojo_ios_smoke.o' || fail "unexpected archive contents: ${archive_path}"
done

log 'creating dual-slice XCFramework'
xcodebuild -create-xcframework \
  -library "${device_archive}" -headers "${headers_root}" \
  -library "${simulator_archive}" -headers "${headers_root}" \
  -output "${xcframework_path}"

[[ -f "${xcframework_path}/Info.plist" ]] || fail 'XCFramework Info.plist was not produced'
xcframework_libraries="$(find "${xcframework_path}" -type f -name 'libmojo_ios_smoke.a' | wc -l | tr -d ' ')"
[[ "${xcframework_libraries}" == '2' ]] || fail "expected two XCFramework libraries, found ${xcframework_libraries}"
plutil -p "${xcframework_path}/Info.plist"
plutil -p "${xcframework_path}/Info.plist" | grep -q '"LibraryIdentifier" => "ios-arm64"' || fail 'XCFramework is missing its device library record'
plutil -p "${xcframework_path}/Info.plist" | grep -q '"LibraryIdentifier" => "ios-arm64-simulator"' || fail 'XCFramework is missing its Simulator library record'

if command -v vtool >/dev/null 2>&1; then
  for expected in 'IOSSIMULATOR' 'IOS'; do
    case "${expected}" in
      IOSSIMULATOR) object_path="${simulator_root}/mojo_ios_smoke.o" ;;
      IOS) object_path="${device_root}/mojo_ios_smoke.o" ;;
    esac
    build_metadata="$(vtool -show-build "${object_path}")"
    printf '%s\n' "${build_metadata}" | sed -n '1,100p'
    printf '%s\n' "${build_metadata}" | grep -q "platform ${expected}" || fail "wrong Mach-O platform for ${object_path}"
  done
else
  log 'SKIP: vtool is unavailable; run xcrun vtool -show-build on the slice objects manually'
fi

log 'creating local Swift Package binary-target wrapper'
mkdir -p "${package_root}/Artifacts" "${package_root}/Sources/MojoIOSSmokeWrapper"
cp -R "${xcframework_path}" "${package_root}/Artifacts/"
cat >"${package_root}/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MojoIOSSmokePackage",
  platforms: [.iOS(.v17)],
  products: [
    .library(name: "MojoIOSSmokeWrapper", targets: ["MojoIOSSmokeWrapper"]),
  ],
  targets: [
    .binaryTarget(
      name: "MojoIOSSmoke",
      path: "Artifacts/MojoIOSSmoke.xcframework"
    ),
    .target(
      name: "MojoIOSSmokeWrapper",
      dependencies: ["MojoIOSSmoke"]
    ),
  ]
)
EOF
cat >"${package_root}/Sources/MojoIOSSmokeWrapper/MojoIOSSmokeWrapper.swift" <<'EOF'
import MojoIOSSmoke

public func mojoAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
  mojo_add(lhs, rhs)
}
EOF
(
  cd "${package_root}"
  swift package describe --type json
)

log "PASS: artifact-only XCFramework created at ${xcframework_path}"
log 'The local Swift Package graph was described, not built for iOS or executed.'
log 'No physical device, signing identity, app installation, or device execution was used.'
