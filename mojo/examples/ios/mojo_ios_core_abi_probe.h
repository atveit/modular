#ifndef MOJO_EXAMPLES_IOS_MOJO_IOS_CORE_ABI_PROBE_H_
#define MOJO_EXAMPLES_IOS_MOJO_IOS_CORE_ABI_PROBE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Deliberately incomplete: native callers cannot observe Mojo's storage type.
typedef struct MojoIOSHandle MojoIOSHandle;

// Ownership transfers to the caller. Every non-null result must be passed
// exactly once to mojo_ios_handle_destroy.
MojoIOSHandle *mojo_ios_handle_create(int64_t value);
int32_t mojo_ios_handle_read(MojoIOSHandle *handle, int64_t *output);
int32_t mojo_ios_handle_destroy(MojoIOSHandle *handle);

// Returns zero on success and writes output. Mojo Error values are caught and
// converted to status 2; they never cross the C ABI.
int32_t mojo_ios_checked_double(int64_t value, int64_t *output);

#ifdef __cplusplus
}
#endif

#endif  // MOJO_EXAMPLES_IOS_MOJO_IOS_CORE_ABI_PROBE_H_
