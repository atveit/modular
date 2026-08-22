import MojoIOSFoundation

@main
struct FoundationConsumer {
    static func main() {
        var isFileURL: Int64 = -1
        let status = mojo_foundation_url_is_file_url("file:///tmp/mojo", &isFileURL)
        guard status == 0, isFileURL == 1 else {
            fatalError("Foundation adapter failed: status=\(status), isFileURL=\(isFileURL)")
        }
        print("MOJO_FOUNDATION_URL_PASS")
    }
}
