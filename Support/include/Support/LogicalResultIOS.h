//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions.
//===----------------------------------------------------------------------===//

#ifndef SUPPORT_LOGICAL_RESULT_IOS_H
#define SUPPORT_LOGICAL_RESULT_IOS_H

#include <optional>

namespace M {

class LogicalResult {
public:
  static LogicalResult success(bool value = true) { return LogicalResult(value); }
  static LogicalResult failure(bool value = true) {
    return LogicalResult(!value);
  }
  explicit operator bool() const { return ok; }

private:
  explicit LogicalResult(bool value) : ok(value) {}
  bool ok;
};

using ParseResult = LogicalResult;
template <typename T> using FailureOr = std::optional<T>;

inline bool succeeded(LogicalResult result) { return bool(result); }
inline bool failed(LogicalResult result) { return !succeeded(result); }
inline LogicalResult success(bool value) { return LogicalResult::success(value); }
inline LogicalResult failure(bool value = true) {
  return LogicalResult::failure(value);
}

struct SuccessType {
  operator LogicalResult() const { return success(true); }
};

inline SuccessType success() { return {}; }

} // namespace M

#endif // SUPPORT_LOGICAL_RESULT_IOS_H
