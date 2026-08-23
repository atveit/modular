//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "AsyncRT/Runtime/Allocator.h"
#include "Support/AlignedAlloc.h"

#include <cstring>

using namespace M;
using namespace M::AsyncRT;

namespace {
class MallocAllocatorIOS final : public Allocator {
  void *allocateBytes(size_t size, size_t alignment) override {
    return alignedAlloc(alignment, size);
  }

  void deallocateBytes(void *ptr, size_t) override { alignedFree(ptr); }
};
} // namespace

std::unique_ptr<Allocator> M::AsyncRT::createMallocAllocator() {
  return std::make_unique<MallocAllocatorIOS>();
}

void M::AsyncRT::profiledMemcpy(void *dst, const void *src, size_t size) {
  std::memcpy(dst, src, size);
}
