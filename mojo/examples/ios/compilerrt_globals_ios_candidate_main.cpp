#include "llvm/ADT/StringRef.h"

#include <assert.h>
#include <atomic>
#include <stddef.h>
#include <stdio.h>
#include <thread>
#include <vector>

extern "C" bool KGEN_CompilerRT_Initialize(void);
extern "C" void *KGEN_CompilerRT_AlignedAlloc(ptrdiff_t alignment,
                                              ptrdiff_t size);
extern "C" void KGEN_CompilerRT_AlignedFree(void *ptr);
extern "C" void *KGEN_CompilerRT_GetOrCreateGlobal(llvm::StringRef name,
                                                   void *(*init_fn)(),
                                                   void (*destroy_fn)(void *));
extern "C" void *KGEN_CompilerRT_GetGlobalOrNull(llvm::StringRef name);
extern "C" void KGEN_CompilerRT_InsertGlobal(llvm::StringRef name, void *value);
extern "C" void *
KGEN_CompilerRT_GetOrCreateGlobalIndexed(size_t index, void *(*init_fn)(),
                                         void (*destroy_fn)(void *));
extern "C" void KGEN_CompilerRT_DestroyGlobals(void);

static std::atomic<int> named_create_count = 0;
static std::atomic<int> named_destroy_count = 0;
static std::atomic<int> indexed_create_count = 0;
static std::atomic<int> indexed_destroy_count = 0;

static void *create_named() {
  ++named_create_count;
  return KGEN_CompilerRT_AlignedAlloc(8, 32);
}
static void destroy_named(void *value) {
  ++named_destroy_count;
  KGEN_CompilerRT_AlignedFree(value);
}
static void *create_indexed() {
  ++indexed_create_count;
  return KGEN_CompilerRT_AlignedAlloc(8, 32);
}
static void destroy_indexed(void *value) {
  ++indexed_destroy_count;
  KGEN_CompilerRT_AlignedFree(value);
}

static void run_concurrent_round() {
  constexpr int kThreadCount = 8;
  constexpr int kIterations = 200;
  llvm::StringRef named("candidate.concurrent.named");
  std::vector<void *> named_results(kThreadCount);
  std::vector<void *> indexed_results(kThreadCount);
  std::vector<std::thread> threads;
  threads.reserve(kThreadCount);
  for (int thread_index = 0; thread_index < kThreadCount; ++thread_index) {
    threads.emplace_back([&, thread_index] {
      void *named_value = nullptr;
      void *indexed_value = nullptr;
      for (int iteration = 0; iteration < kIterations; ++iteration) {
        void *next_named = KGEN_CompilerRT_GetOrCreateGlobal(
            named, create_named, destroy_named);
        void *next_indexed = KGEN_CompilerRT_GetOrCreateGlobalIndexed(
            1, create_indexed, destroy_indexed);
        assert(next_named != nullptr);
        assert(next_indexed != nullptr);
        assert(named_value == nullptr || named_value == next_named);
        assert(indexed_value == nullptr || indexed_value == next_indexed);
        named_value = next_named;
        indexed_value = next_indexed;
      }
      named_results[thread_index] = named_value;
      indexed_results[thread_index] = indexed_value;
    });
  }
  for (std::thread &thread : threads)
    thread.join();
  for (int thread_index = 1; thread_index < kThreadCount; ++thread_index) {
    assert(named_results[thread_index] == named_results[0]);
    assert(indexed_results[thread_index] == indexed_results[0]);
  }
}

int main() {
  assert(KGEN_CompilerRT_Initialize());
  llvm::StringRef named("candidate.named");
  void *first =
      KGEN_CompilerRT_GetOrCreateGlobal(named, create_named, destroy_named);
  assert(first != nullptr);
  assert(KGEN_CompilerRT_GetOrCreateGlobal(named, create_named,
                                           destroy_named) == first);
  assert(KGEN_CompilerRT_GetGlobalOrNull(named) == first);
  void *inserted = KGEN_CompilerRT_AlignedAlloc(8, 32);
  llvm::StringRef inserted_name("candidate.inserted");
  KGEN_CompilerRT_InsertGlobal(inserted_name, inserted);
  assert(KGEN_CompilerRT_GetGlobalOrNull(inserted_name) == inserted);
  void *indexed = KGEN_CompilerRT_GetOrCreateGlobalIndexed(0, create_indexed,
                                                           destroy_indexed);
  assert(indexed != nullptr);
  assert(KGEN_CompilerRT_GetOrCreateGlobalIndexed(0, create_indexed,
                                                  destroy_indexed) == indexed);
  KGEN_CompilerRT_DestroyGlobals();
  assert(named_destroy_count.load() == 1);
  assert(indexed_destroy_count.load() == 1);
  assert(KGEN_CompilerRT_GetGlobalOrNull(named) == nullptr);
  KGEN_CompilerRT_DestroyGlobals();
  assert(named_destroy_count.load() == 1);
  assert(indexed_destroy_count.load() == 1);
  KGEN_CompilerRT_AlignedFree(inserted);

  constexpr int kRounds = 64;
  for (int round = 0; round < kRounds; ++round) {
    run_concurrent_round();
    KGEN_CompilerRT_DestroyGlobals();
  }
  assert(named_create_count.load() == kRounds + 1);
  assert(named_destroy_count.load() == kRounds + 1);
  assert(indexed_create_count.load() == kRounds + 1);
  assert(indexed_destroy_count.load() == kRounds + 1);
  puts("MOJO_COMPILERRT_GLOBALS_IOS_CANDIDATE_PASS");
  return 0;
}
