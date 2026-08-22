#ifndef MOJO_IOS_FOUNDATION_H
#define MOJO_IOS_FOUNDATION_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Parses a caller-owned UTF-8 URL string through Foundation. NSString and
// NSURL remain adapter-owned; the function returns 0 and writes 0/1 for
// NSURL.isFileURL, or returns 1 for invalid arguments, 2 for invalid UTF-8,
// and 3 for an invalid URL.
int32_t mojo_foundation_url_is_file_url(const char *utf8,
                                        int64_t *is_file_url_out);

#ifdef __cplusplus
}
#endif

#endif // MOJO_IOS_FOUNDATION_H
