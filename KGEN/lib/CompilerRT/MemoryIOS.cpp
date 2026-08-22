//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

// The iOS static CompilerRT target must not pull in AsyncRT's TCMalloc globals.
// Keep this file limited to the two allocation ABI entry points lowered by
// pop.aligned_alloc/pop.aligned_free. It is deliberately not part of the
// desktop CompilerRT shared library.

#include <cstddef>
#include <cstdlib>
#include <sys/types.h>

#include "Support/SymbolExport.h"

namespace {
constexpr size_t kIOSPreferredMemoryAlignment = 16;

bool isPowerOfTwo(size_t alignment) {
  return alignment != 0 && (alignment & (alignment - 1)) == 0;
}
} // namespace

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *
KGEN_CompilerRT_AlignedAlloc(ssize_t alignment, ssize_t size) {
  if (size < 0)
    return nullptr;

  const size_t requestedAlignment =
      alignment <= 0 ? kIOSPreferredMemoryAlignment : size_t(alignment);
  if (!isPowerOfTwo(requestedAlignment))
    return nullptr;

  // malloc meets any alignment no larger than max_align_t. This also accepts
  // the small (for example, byte) power-of-two alignments lowered for String.
  if (requestedAlignment <= alignof(std::max_align_t))
    return std::malloc(size_t(size));

  void *ptr = nullptr;
  return posix_memalign(&ptr, requestedAlignment, size_t(size)) == 0 ? ptr
                                                                     : nullptr;
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_AlignedFree(void *ptr) {
  std::free(ptr);
}
