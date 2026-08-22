#ifndef MOJO_IOS_UIKIT_H
#define MOJO_IOS_UIKIT_H

#ifdef __cplusplus
extern "C" {
#endif

// Returns the main UIScreen scale as a scalar. UIKit object ownership remains
// within the Objective-C adapter; callers do not receive a UIKit handle.
double mojo_uikit_main_screen_scale(void);

#ifdef __cplusplus
}
#endif

#endif // MOJO_IOS_UIKIT_H
