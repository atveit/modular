#include "mojo_ios_os_signpost.h"

#include <os/signpost.h>

int32_t mojo_os_signpost_emit(void) {
  // A fixed literal avoids variadic formatting across the ABI. OS_LOG_DEFAULT
  // is framework-owned; this adapter neither creates nor releases an object.
  os_signpost_event_emit(OS_LOG_DEFAULT, OS_SIGNPOST_ID_EXCLUSIVE,
                         "mojo_ios_direct_c_event");
  return 0;
}
