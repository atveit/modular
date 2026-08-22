#ifndef MODULAR_MOJO_IOS_RUNTIME_STRING_H_
#define MODULAR_MOJO_IOS_RUNTIME_STRING_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Creates and destroys a Mojo String internally; no Mojo-owned value crosses
// the C ABI. Requires an iOS-compatible static Mojo runtime at link/run time.
int64_t mojo_runtime_string_byte_count(int64_t value);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_RUNTIME_STRING_H_
