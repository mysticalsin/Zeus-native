import Foundation

@main
struct HistoryMain {
    static func main() {
        let store = DictationStore(root: URL(fileURLWithPath: "/tmp/unused-dictation"))
        let decoder = JSONEncoder()
        decoder.dateEncodingStrategy = .iso8601
        var reads = 0
        let source = DictationStore.DictationHistorySource(
            entries: {
                (0..<80).map { index in
                    (URL(fileURLWithPath: "/history/\(index)"), Date(timeIntervalSince1970: TimeInterval(index)))
                }
            },
            read: { url in
                reads += 1
                let index = Int(url.lastPathComponent) ?? 0
                let record = DictationRecord(
                    id: "\(index)", datetime: Date(timeIntervalSince1970: TimeInterval(index)),
                    duration: 1, processingTime: 1, modeKey: "plain", modeName: "Plain",
                    rawResult: "a", result: "a")
                return try? decoder.encode(record)
            })
        let load = store.loadHistory(limit: 50, source: source)
        if reads > 50 {
            fputs("FAIL read \(reads) metadata files for a limit of 50\n", stderr)
            exit(1)
        }
        if load.records.count != 50 {
            fputs("FAIL kept \(load.records.count)\n", stderr)
            exit(1)
        }
        if load.records.first?.id != "79" {
            fputs("FAIL newest is \(load.records.first?.id ?? "nil")\n", stderr)
            exit(1)
        }
        fputs("history reads \(reads)\n", stderr)
    }
}
