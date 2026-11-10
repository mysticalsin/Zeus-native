import Foundation
import ZeusCore

/// `zeus insomnia-guard`: the lid-closed backstop launchd runs every 60 s. If the journal shows a
/// session past its end, or the Zeus that started it is gone, it puts everything back (sleep, Low
/// Power, frozen apps, sound) and clears the journal. Safe and silent with no journal; idempotent.
enum InsomniaGuardCommand {
    static func run(_ args: [String]) -> Int32 {
        let store = InsomniaJournalStore()
        let restorer = InsomniaRestorer(runner: ProcessCommandRunner(), store: store)
        let outcome = InsomniaGuard.run(restorer: restorer) { InsomniaProcessProbe.isAlive($0) }
        switch outcome {
        case .noJournal, .sessionHealthy:
            if args.contains("--verbose") { print(InsomniaGuard.describe(outcome)) }
            return 0
        case .unreadableJournal:
            print("\(Date().ISO8601Format()) \(InsomniaGuard.describe(outcome))")
            return 0
        case .restored(_, let report):
            print("\(Date().ISO8601Format()) \(InsomniaGuard.describe(outcome))")
            return report.journalCleared ? 0 : 1
        }
    }
}
