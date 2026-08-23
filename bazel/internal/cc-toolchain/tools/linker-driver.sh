#!/bin/bash
##===----------------------------------------------------------------------===##
# Copyright (c) 2026, Modular Inc. All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##===----------------------------------------------------------------------===##

set -euo pipefail

if [[ $OSTYPE == darwin* ]]; then
  platform=macos
else
  platform="linux-$(uname -m)"
fi

clang_root="$PWD/external/+http_archive+clang-$platform"
# File paths in tests differ
if [[ ! -d "$clang_root" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$script_dir/../../../.."
  clang_root="$repo_root/../+http_archive+clang-$platform"
fi

readonly clang="$clang_root/bin/clang++"
readonly dsymutil="$clang_root/bin/dsymutil"

ifs_input=""
ifs_output=""
dsym_path=""
binary_path=""
linker_args=()
for arg in "$@"; do
  case "$arg" in
    --modular-ifs-input=*) ifs_input="${arg#*=}" ;;
    --modular-ifs-output=*) ifs_output="${arg#*=}" ;;
    --modular-dsym-path=*) dsym_path="${arg#*=}" ;;
    --modular-binary-path=*) binary_path="${arg#*=}" ;;
    *) linker_args+=("$arg") ;;
  esac
done

linker="$clang"
for arg in "${linker_args[@]}"; do
  if [[ "$arg" == --target=*-apple-ios* ]]; then
    if [[ "$arg" == *-simulator ]]; then
      apple_sdk="iphonesimulator"
    else
      apple_sdk="iphoneos"
    fi
    developer_dir="$(/usr/bin/xcode-select -p)"
    sdk_root="$(/usr/bin/xcrun --sdk "$apple_sdk" --show-sdk-path)"
    apple_linker_args=()
    for linker_arg in "${linker_args[@]}"; do
      # Let Xcode clang select its matching CompilerRT. The repository Clang
      # resource directory does not contain Apple's iOS/iOSSimulator builtins.
      if [[ "$linker_arg" == -resource-dir=* ]]; then
        continue
      fi
      linker_arg="${linker_arg//__BAZEL_XCODE_DEVELOPER_DIR__/$developer_dir}"
      linker_arg="${linker_arg//__BAZEL_XCODE_SDKROOT__/$sdk_root}"
      apple_linker_args+=("$linker_arg")
    done
    linker="/usr/bin/xcrun"
    linker_args=(--sdk "$apple_sdk" clang++ "${apple_linker_args[@]}")
    break
  fi
done

"$linker" "${linker_args[@]}"

if [[ -n "$dsym_path" ]]; then
  "$dsymutil" -o "$dsym_path" "$binary_path"
fi

if [[ "${BUILD_IFS:-}" == "yes" ]]; then
  if [[ -z "$ifs_input" || -z "$ifs_output" ]]; then
    echo "error: interface library input and output paths are required" >&2
    exit 1
  fi

  if [[ $OSTYPE == darwin* ]]; then
    ifs_platform=mac
  elif [[ $(uname -m) == "x86_64" ]]; then
    ifs_platform=intel
  else
    ifs_platform=graviton
  fi

  ifs_root="$PWD/external/+http_archive+llvm-ifs/tools/$ifs_platform"

  if [[ "${MACOS:-}" == "true" ]]; then
    "$ifs_root/llvm-readtapi.stripped" -arch arm64 -extract "$ifs_input" -o "$ifs_output"
  else
    "$ifs_root/llvm-ifs.stripped" "$ifs_input" --output-elf="$ifs_output"
  fi
fi
