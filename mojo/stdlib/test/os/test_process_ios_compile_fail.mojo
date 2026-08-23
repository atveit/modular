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

# RUN: not %bare-mojo build --target-triple=arm64-apple-ios17.0-simulator --target-cpu=apple-m1 --emit=llvm %s -o /dev/null 2>&1 | FileCheck %s
# RUN: not %bare-mojo build --target-triple=arm64-apple-ios17.0 --target-cpu=apple-a7 --emit=llvm %s -o /dev/null 2>&1 | FileCheck %s

from std.collections import List
from std.os import Process


# CHECK: constraint failed: Current compilation target does not support operation: process execution. Note: iOS applications cannot spawn subprocesses
def main() raises:
    _ = Process.run("echo", List[String]())
