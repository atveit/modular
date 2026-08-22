#include "mojo_ios_corefoundation.h"

#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>

int32_t mojo_corefoundation_utf16_length(const char *utf8,
                                         int64_t *length_out) {
  if (utf8 == NULL || length_out == NULL) {
    return 1;
  }

  CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, utf8,
                                                kCFStringEncodingUTF8);
  if (value == NULL) {
    return 2;
  }

  const CFIndex length = CFStringGetLength(value);
  CFRelease(value);
  if (length < 0 || length > INT64_MAX) {
    return 3;
  }
  *length_out = (int64_t)length;
  return 0;
}
