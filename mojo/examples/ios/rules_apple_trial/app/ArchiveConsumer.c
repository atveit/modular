#include "mojo_ios_static_library_smoke.h"

int64_t archive_consumer_add(int64_t lhs, int64_t rhs) {
  return mojo_add(lhs, rhs);
}
