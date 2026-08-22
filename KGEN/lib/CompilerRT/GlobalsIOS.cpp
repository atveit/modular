//===----------------------------------------------------------------------===//
// iOS candidate for the CompilerRT global ABI.
//
// This is intentionally separate from Globals.cpp. It preserves the exported
// entry points and their basic named/indexed lifecycle semantics without the
// desktop GlobalTable or LLVM Support library. It is not a replacement for the
// desktop lock-free implementation: concurrent destruction and its allocation/
// contention characteristics have not been established for this candidate.
//===----------------------------------------------------------------------===//

#include "Support/SymbolExport.h"
#include "llvm/ADT/StringRef.h"

#include <array>
#include <atomic>
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

std::mutex &namedMutex() {
  static std::mutex mutex;
  return mutex;
}

std::unordered_map<std::string, NamedEntry> &namedEntries() {
  static std::unordered_map<std::string, NamedEntry> entries;
  return entries;
}

std::vector<std::string> &namedDestructionOrder() {
  static std::vector<std::string> order;
  return order;
}

thread_local void *insertValue = nullptr;

void *getOrCreateNamed(llvm::StringRef name, void *(*initFn)(),
                       void (*destroyFn)(void *)) {
  std::lock_guard<std::mutex> lock(namedMutex());
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
  std::atomic<void *> value{nullptr};
  std::atomic<void (*)(void *)> destroyFn{nullptr};

  void destroy() {
    void *oldValue = value.exchange(nullptr, std::memory_order_acq_rel);
    void (*oldDestroy)(void *) =
        destroyFn.exchange(nullptr, std::memory_order_acq_rel);
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
  insertValue = value;
  (void)getOrCreateNamed(name, [] { return insertValue; }, nullptr);
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *
KGEN_CompilerRT_GetOrCreateGlobalIndexed(size_t index, void *(*initFn)(),
                                         void (*destroyFn)(void *)) {
  assert(index < kNumIndexedGlobals && "Unsupported indexed global #");
  IndexedEntry &entry = indexedEntries[index];
  if (void *existing = entry.value.load(std::memory_order_acquire))
    return existing;
  if (!initFn)
    return nullptr;
  void *created = initFn();
  if (!created)
    return nullptr;
  void *expected = nullptr;
  if (!entry.value.compare_exchange_strong(expected, created,
                                            std::memory_order_acq_rel)) {
    if (destroyFn)
      destroyFn(created);
    return expected;
  }
  entry.destroyFn.store(destroyFn, std::memory_order_release);
  return created;
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_DestroyGlobals() {
  std::unordered_map<std::string, NamedEntry> entries;
  std::vector<std::string> order;
  {
    std::lock_guard<std::mutex> lock(namedMutex());
    entries.swap(namedEntries());
    order.swap(namedDestructionOrder());
  }
  for (auto it = order.rbegin(); it != order.rend(); ++it) {
    auto entry = entries.find(*it);
    if (entry != entries.end() && entry->second.value && entry->second.destroyFn)
      entry->second.destroyFn(entry->second.value);
  }
  for (IndexedEntry &entry : indexedEntries)
    entry.destroy();
}
