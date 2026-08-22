#ifndef MODULAR_MOJO_IOS_ACCELERATE_H_
#define MODULAR_MOJO_IOS_ACCELERATE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Adds count caller-owned float values using Apple's vDSP implementation.
// Returns 0 on success, -1 for a negative count, and -2 for a null pointer
// when count is non-zero. No allocation or ownership transfer occurs.
int32_t mojo_accelerate_vector_add(const float *lhs, const float *rhs,
                                   float *out, int64_t count);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_ACCELERATE_H_
