//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "Support/Error.h"

#include <cstring>

bool M::operator==(const Error &lhs, const Error &rhs) {
  return std::strcmp(lhs.get(), rhs.get()) == 0;
}
