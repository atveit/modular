#ifndef MOJO_IOS_COREFOUNDATION_H
#define MOJO_IOS_COREFOUNDATION_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Creates a CFString from a UTF-8 C string, writes its UTF-16 code-unit count,
// and releases it before returning. The caller owns neither a CF object nor
// the input buffer. Returns 0 on success, 1 for invalid arguments, 2 if
// CoreFoundation could not create the string, or 3 if the length is
// unrepresentable.
int32_t mojo_corefoundation_utf16_length(const char *utf8, int64_t *length_out);

#ifdef __cplusplus
}
#endif

#endif // MOJO_IOS_COREFOUNDATION_H
