import MojoIOSOSSignpost

@main
struct OSSignpostConsumer {
    static func main() {
        precondition(mojo_os_signpost_emit() == 0)
    }
}
