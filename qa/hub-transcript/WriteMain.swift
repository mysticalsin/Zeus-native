import Foundation

@main
struct WriteMain {
    static func main() {
        if HubTranscriptBudget.prettyPrinted {
            fputs("FAIL transcript JSON is pretty-printed\n", stderr)
            exit(1)
        }
        if HubTranscriptBudget.keptLines(500) != HubTranscriptBudget.lineCap {
            fputs("FAIL kept \(HubTranscriptBudget.keptLines(500))\n", stderr)
            exit(1)
        }
        if HubTranscriptBudget.keptLines(12) != 12 {
            fputs("FAIL a short transcript was trimmed\n", stderr)
            exit(1)
        }
        fputs("transcript budget ok\n", stderr)
    }
}
