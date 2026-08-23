//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#include "Support/TypeID.h"

using namespace M;

Detail::RawTypeID Detail::TypeInfoTable::getSlow(
    std::string_view typeName, ValueDestructorFn destructor) {
  std::lock_guard<std::mutex> lock(mu);
  auto found = ids.find(std::string(typeName));
  if (found != ids.end())
    return found->second;

  size_t id = entries.emplace_back(typeName, destructor);
  assert(id != Detail::kInvalidRawTypeID && "too many type ids registered");
  ids.emplace(std::string(typeName), id);
  return id;
}

Detail::RawTypeID TypeID::getSlow(std::string_view typeName,
                                  ValueDestructorFn destructor) {
  return Detail::TypeInfoTable::getSingleton().getSlow(typeName, destructor);
}
