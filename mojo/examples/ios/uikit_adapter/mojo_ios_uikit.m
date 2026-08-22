#import <UIKit/UIKit.h>

#include "mojo_ios_uikit.h"

double mojo_uikit_main_screen_scale(void) {
  @autoreleasepool {
    return UIScreen.mainScreen.scale;
  }
}
