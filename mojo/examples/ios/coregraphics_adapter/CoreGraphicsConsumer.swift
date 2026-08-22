import MojoIOSCoreGraphics

@main
struct CoreGraphicsConsumer {
    static func main() {
        precondition(mojo_coregraphics_rect_area(3.0, 4.0) == 12.0)
        print("MOJO_COREGRAPHICS_RECT_PASS")
    }
}
