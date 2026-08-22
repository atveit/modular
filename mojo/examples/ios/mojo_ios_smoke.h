#ifndef MODULAR_MOJO_IOS_SMOKE_H_
#define MODULAR_MOJO_IOS_SMOKE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The first stable boundary is intentionally scalar/POD and caller-owned.
int64_t mojo_add(int64_t lhs, int64_t rhs);

// Returns the required UTF-8 byte count.  If output is non-null and capacity
// is positive, at most capacity bytes are written; no NUL terminator is
// promised or required by this API.
int64_t mojo_hello_utf8(uint8_t *output, int64_t capacity);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_SMOKE_H_
