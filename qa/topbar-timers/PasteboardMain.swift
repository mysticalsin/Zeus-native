import Foundation

@main
struct PasteboardMain {
    static func main() {
        var watch = PasteboardWatch()
        if watch.note(4) == false {
            fputs("FAIL the first count was ignored\n", stderr)
            exit(1)
        }
        if watch.note(4) {
            fputs("FAIL an unchanged count woke the reader\n", stderr)
            exit(1)
        }
        if watch.note(5) == false {
            fputs("FAIL a new count was ignored\n", stderr)
            exit(1)
        }
        fputs("pasteboard watch ok\n", stderr)
    }
}
