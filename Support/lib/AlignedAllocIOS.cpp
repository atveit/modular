//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "Support/AlignedAlloc.h"

#include <cstddef>
#include <cstdlib>

void *M::alignedAlloc(size_t alignment, size_t size) {
  if (size == 0)
    return nullptr;
  if (alignment <= alignof(std::max_align_t))
    return std::malloc(size);
  void *ptr = nullptr;
  return posix_memalign(&ptr, alignment, size) == 0 ? ptr : nullptr;
}
