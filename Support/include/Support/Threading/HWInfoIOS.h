//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#ifndef SUPPORT_THREADING_HWINFO_IOS_H
#define SUPPORT_THREADING_HWINFO_IOS_H

#include <cstddef>

namespace M {

constexpr size_t kNoAffinity = ~size_t(0);
constexpr int kAnyNumaNode = -1;

} // namespace M

#endif // SUPPORT_THREADING_HWINFO_IOS_H
