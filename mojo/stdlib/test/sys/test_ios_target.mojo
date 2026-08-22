# ===----------------------------------------------------------------------=== #
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
# ===----------------------------------------------------------------------=== #
#
# Cross-target compile coverage for the iOS target predicates. The test is
# intentionally object/LLVM-only: linking and running an iOS binary belongs to
# the iOS toolchain and Simulator integration tests.
#
# RUN: %bare-mojo build --target-triple=arm64-apple-ios17.0-simulator --target-cpu=apple-m1 -D EXPECT_SIMULATOR --emit=llvm %s -o /dev/null
# RUN: %bare-mojo build --target-triple=arm64-apple-ios17.0 --target-cpu=apple-a7 --emit=llvm %s -o /dev/null

from std.sys import CompilationTarget, is_defined
from std.sys._libc_errno import ErrNo
from std.sys.info import platform_map
from std.time import perf_counter_ns


comptime _darwin_map = platform_map[
    T=Int,
    "test platform map",
    linux=1,
    macos=2,
    ios=3,
    darwin=4,
]()

comptime _darwin_fallback = platform_map[
    T=Int,
    "test Darwin fallback",
    darwin=4,
]()


def main() raises:
    comptime assert CompilationTarget.is_ios()
    comptime assert CompilationTarget.is_darwin()
    comptime assert _darwin_map == 3
    comptime assert _darwin_fallback == 4
    comptime assert ErrNo.EAGAIN.value == 35
    comptime assert ErrNo.ENOTSUP.value == 45

    # On Darwin-family targets this lowers to the platform C API
    # `clock_gettime_nsec_np`, which is available on iOS 17 and later.
    _ = perf_counter_ns()

    comptime if is_defined["EXPECT_SIMULATOR"]():
        comptime assert CompilationTarget.is_ios_simulator()
    else:
        comptime assert not CompilationTarget.is_ios_simulator()
