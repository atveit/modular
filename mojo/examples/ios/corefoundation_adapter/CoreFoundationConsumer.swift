import MojoIOSCoreFoundation

@main
struct CoreFoundationConsumer {
    static func main() {
        var length: Int64 = -1
        let status = mojo_corefoundation_utf16_length("Mojo", &length)
        guard status == 0, length == 4 else {
            fatalError("CoreFoundation adapter failed: status=\(status), length=\(length)")
        }
        print("MOJO_COREFOUNDATION_CFSTRING_PASS")
    }
}
