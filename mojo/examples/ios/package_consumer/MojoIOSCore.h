#ifndef MODULAR_MOJO_IOS_CORE_H_
#define MODULAR_MOJO_IOS_CORE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// These package-level functions keep CompilerRT names out of the Swift API.
// The bounded serial core is initialized before each Mojo call.
int64_t mojo_ios_package_add(int64_t lhs, int64_t rhs);
int64_t mojo_ios_package_hello_utf8(uint8_t *output, int64_t capacity);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_CORE_H_
