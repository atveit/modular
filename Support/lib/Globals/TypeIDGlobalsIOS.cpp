//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "Support/Globals/Globals.h"
#include "Support/TypeID.h"

M::Detail::TypeInfoTable &M::Globals::getTypeInfoTableSingleton(
    const std::function<Detail::TypeInfoTable *()> &ctor) {
  static Detail::TypeInfoTable *table = ctor();
  return *table;
}
