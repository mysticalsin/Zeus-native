import Foundation
import ZeusCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var outPath = "qa/O38/silent-eval-last.json"
var args = Array(CommandLine.arguments.dropFirst())
while let first = args.first {
    if first == "--out", args.count >= 2 {
        outPath = args[1]
        args.removeFirst(2)
    } else if first == "--help" || first == "-h" {
        print("""
        zeus-silent-eval: fake-Mac dry eval gate (O38). No real Mac actions, no AI spend.

        Usage: zeus-silent-eval [--out path]

        Writes JSON with pass/fail per scenario. Exit 0 only when all pass.
        """)
        exit(0)
    } else {
        fail("unknown argument: \(first)")
    }
}

let report = SilentEvalHarness.runAll()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
guard let data = try? encoder.encode(report) else { fail("could not encode report") }

let url = URL(fileURLWithPath: outPath, isDirectory: false)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
do {
    try data.write(to: url, options: .atomic)
} catch {
    fail("could not write \(outPath): \(error)")
}

for row in report.scenarios {
    let mark = row.ok ? "PASS" : "FAIL"
    print("\(row.id.padding(toLength: 28, withPad: " ", startingAt: 0)) \(mark)  \(row.notes)")
}
print("\nJSON: \(outPath)")
print("pass=\(report.pass) scenarios=\(report.scenarios.count)")
exit(report.pass ? 0 : 1)
