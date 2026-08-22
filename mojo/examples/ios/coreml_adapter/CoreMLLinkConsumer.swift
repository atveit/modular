import MojoIOSCoreML

@main
struct CoreMLLinkConsumer {
    static func main() {
        // Deliberately do not call mojo_coreml_framework_anchor(). This target
        // is link/artifact evidence only, not a Core ML runtime smoke test.
    }
}
