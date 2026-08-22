#include "llvm/ADT/StringRef.h"

#include <assert.h>
#include <stddef.h>
#include <stdio.h>

extern "C" bool KGEN_CompilerRT_Initialize(void);
extern "C" void *KGEN_CompilerRT_AlignedAlloc(ptrdiff_t alignment,
                                                ptrdiff_t size);
extern "C" void KGEN_CompilerRT_AlignedFree(void *ptr);
extern "C" void *KGEN_CompilerRT_GetOrCreateGlobal(
    llvm::StringRef name, void *(*init_fn)(), void (*destroy_fn)(void *));
extern "C" void *KGEN_CompilerRT_GetGlobalOrNull(llvm::StringRef name);
extern "C" void KGEN_CompilerRT_InsertGlobal(llvm::StringRef name, void *value);
extern "C" void *KGEN_CompilerRT_GetOrCreateGlobalIndexed(
    size_t index, void *(*init_fn)(), void (*destroy_fn)(void *));
extern "C" void KGEN_CompilerRT_DestroyGlobals(void);

static int named_destroy_count = 0;
static int indexed_destroy_count = 0;

static void *create_named() { return KGEN_CompilerRT_AlignedAlloc(8, 32); }
static void destroy_named(void *value) {
  ++named_destroy_count;
  KGEN_CompilerRT_AlignedFree(value);
}
static void *create_indexed() { return KGEN_CompilerRT_AlignedAlloc(8, 32); }
static void destroy_indexed(void *value) {
  ++indexed_destroy_count;
  KGEN_CompilerRT_AlignedFree(value);
}

int main() {
  assert(KGEN_CompilerRT_Initialize());
  llvm::StringRef named("candidate.named");
  void *first = KGEN_CompilerRT_GetOrCreateGlobal(named, create_named, destroy_named);
  assert(first != nullptr);
  assert(KGEN_CompilerRT_GetOrCreateGlobal(named, create_named, destroy_named) == first);
  assert(KGEN_CompilerRT_GetGlobalOrNull(named) == first);
  void *inserted = KGEN_CompilerRT_AlignedAlloc(8, 32);
  llvm::StringRef inserted_name("candidate.inserted");
  KGEN_CompilerRT_InsertGlobal(inserted_name, inserted);
  assert(KGEN_CompilerRT_GetGlobalOrNull(inserted_name) == inserted);
  void *indexed = KGEN_CompilerRT_GetOrCreateGlobalIndexed(
      0, create_indexed, destroy_indexed);
  assert(indexed != nullptr);
  assert(KGEN_CompilerRT_GetOrCreateGlobalIndexed(0, create_indexed,
                                                   destroy_indexed) == indexed);
  KGEN_CompilerRT_DestroyGlobals();
  assert(named_destroy_count == 1);
  assert(indexed_destroy_count == 1);
  assert(KGEN_CompilerRT_GetGlobalOrNull(named) == nullptr);
  KGEN_CompilerRT_DestroyGlobals();
  assert(named_destroy_count == 1);
  assert(indexed_destroy_count == 1);
  KGEN_CompilerRT_AlignedFree(inserted);
  puts("MOJO_COMPILERRT_GLOBALS_IOS_CANDIDATE_PASS");
  return 0;
}
