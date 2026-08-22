#include "mojo_ios_accelerate.h"

#include <Accelerate/Accelerate.h>

int32_t mojo_accelerate_vector_add(const float *lhs, const float *rhs,
                                   float *out, int64_t count) {
  if (count < 0) {
    return -1;
  }
  if (count == 0) {
    return 0;
  }
  if (lhs == 0 || rhs == 0 || out == 0) {
    return -2;
  }

  vDSP_vadd(lhs, 1, rhs, 1, out, 1, (vDSP_Length)count);
  return 0;
}
