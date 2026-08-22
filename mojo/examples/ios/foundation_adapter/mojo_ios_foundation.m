#import <Foundation/Foundation.h>

#include "mojo_ios_foundation.h"

int32_t mojo_foundation_url_is_file_url(const char *utf8,
                                        int64_t *is_file_url_out) {
  if (utf8 == NULL || is_file_url_out == NULL) {
    return 1;
  }

  @autoreleasepool {
    NSString *string = [[NSString alloc] initWithUTF8String:utf8];
    if (string == nil) {
      return 2;
    }
    NSURL *url = [NSURL URLWithString:string];
    if (url == nil) {
      return 3;
    }
    *is_file_url_out = url.isFileURL ? 1 : 0;
  }
  return 0;
}
