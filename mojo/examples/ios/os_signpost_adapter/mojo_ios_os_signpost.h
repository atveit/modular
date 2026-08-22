#ifndef MODULAR_MOJO_IOS_OS_SIGNPOST_H_
#define MODULAR_MOJO_IOS_OS_SIGNPOST_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Emits a fixed-name public os_signpost event to OS_LOG_DEFAULT. It transfers
// no object, string, handle, callback, or ownership across the C ABI.
// Returns 0 after submitting the event.
int32_t mojo_os_signpost_emit(void);

#ifdef __cplusplus
}
#endif

#endif  // MODULAR_MOJO_IOS_OS_SIGNPOST_H_
