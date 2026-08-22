import MojoIOSUIKit

@main
struct UIKitConsumer {
    static func main() {
        let scale = mojo_uikit_main_screen_scale()
        guard scale >= 1.0 else {
            fatalError("UIKit main-screen scale must be positive: \(scale)")
        }
        print("MOJO_UIKIT_SCREEN_SCALE_PASS")
    }
}
