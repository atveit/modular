//===----------------------------------------------------------------------===//
// iOS candidate for the CompilerRT global ABI.
//
// This is intentionally separate from Globals.cpp. It preserves the exported
// entry points and their basic named/indexed lifecycle semantics without the
// desktop GlobalTable or LLVM Support library. It is not a replacement for the
// desktop lock-free implementation. The serial iOS core instead uses one
// recursive mutex so creation, lookup, insertion, and process-lifetime teardown
// have a simple race-free contract. Performance remains a later measurement.
//===----------------------------------------------------------------------===//

#include "Support/SymbolExport.h"
#include "llvm/ADT/StringRef.h"

#include <array>
#include <cassert>
#include <cstddef>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

struct NamedEntry {
  void *value;
  void (*destroyFn)(void *);
};

std::recursive_mutex &globalMutex() {
  static std::recursive_mutex mutex;
  return mutex;
}

bool &isDestroyingGlobals() {
  static bool destroying = false;
  return destroying;
}

std::unordered_map<std::string, NamedEntry> &namedEntries() {
  static std::unordered_map<std::string, NamedEntry> entries;
  return entries;
}

std::vector<std::string> &namedDestructionOrder() {
  static std::vector<std::string> order;
  return order;
}

void *getOrCreateNamed(llvm::StringRef name, void *(*initFn)(),
                       void (*destroyFn)(void *)) {
  std::lock_guard<std::recursive_mutex> lock(globalMutex());
  if (isDestroyingGlobals())
    return nullptr;
  std::string key(name.data(), name.size());
  auto &entries = namedEntries();
  if (auto existing = entries.find(key); existing != entries.end())
    return existing->second.value;
  if (!initFn)
    return nullptr;
  void *value = initFn();
  if (!value)
    return nullptr;
  entries.emplace(key, NamedEntry{value, destroyFn});
  namedDestructionOrder().push_back(std::move(key));
  return value;
}

struct IndexedEntry {
  void *value = nullptr;
  void (*destroyFn)(void *) = nullptr;

  void destroy() {
    void *oldValue = std::exchange(value, nullptr);
    void (*oldDestroy)(void *) = std::exchange(destroyFn, nullptr);
    if (oldValue && oldDestroy)
      oldDestroy(oldValue);
  }
};

constexpr size_t kNumIndexedGlobals = 3;
std::array<IndexedEntry, kNumIndexedGlobals> indexedEntries;

} // namespace

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *
KGEN_CompilerRT_GetOrCreateGlobal(llvm::StringRef name, void *(*initFn)(),
                                  void (*destroyFn)(void *)) {
  return getOrCreateNamed(name, initFn, destroyFn);
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *
KGEN_CompilerRT_GetGlobalOrNull(llvm::StringRef name) {
  return getOrCreateNamed(name, nullptr, nullptr);
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_InsertGlobal(llvm::StringRef name, void *value) {
  std::lock_guard<std::recursive_mutex> lock(globalMutex());
  if (isDestroyingGlobals())
    return;
  std::string key(name.data(), name.size());
  auto [unused, inserted] =
      namedEntries().emplace(key, NamedEntry{value, nullptr});
  (void)unused;
  if (inserted)
    namedDestructionOrder().push_back(std::move(key));
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *
KGEN_CompilerRT_GetOrCreateGlobalIndexed(size_t index, void *(*initFn)(),
                                         void (*destroyFn)(void *)) {
  assert(index < kNumIndexedGlobals && "Unsupported indexed global #");
  std::lock_guard<std::recursive_mutex> lock(globalMutex());
  if (isDestroyingGlobals())
    return nullptr;
  IndexedEntry &entry = indexedEntries[index];
  if (entry.value)
    return entry.value;
  if (!initFn)
    return nullptr;
  void *created = initFn();
  if (!created)
    return nullptr;
  entry.value = created;
  entry.destroyFn = destroyFn;
  return created;
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_DestroyGlobals() {
  std::lock_guard<std::recursive_mutex> lock(globalMutex());
  if (isDestroyingGlobals())
    return;
  isDestroyingGlobals() = true;
  auto &entries = namedEntries();
  auto &order = namedDestructionOrder();
  for (auto it = order.rbegin(); it != order.rend(); ++it) {
    auto entry = entries.find(*it);
    if (entry != entries.end() && entry->second.value &&
        entry->second.destroyFn)
      entry->second.destroyFn(entry->second.value);
  }
  entries.clear();
  order.clear();
  for (IndexedEntry &entry : indexedEntries)
    entry.destroy();
  isDestroyingGlobals() = false;
}
