import Foundation
import Testing
import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Bounded local helper execution")
struct BoundedSubprocessTests {
    @Test func pipesDrainConcurrentlyAndPreserveTheRealExitStatus() {
        let result = BoundedSubprocess.run("/bin/sh", ["-c", "cat; printf 'problem' >&2; exit 7"],
                                           input: Data("Résumé 🦉".utf8), timeout: 2)
        #expect(result.status == 7)
        #expect(result.output == "Résumé 🦉")
        #expect(result.error == "problem")
    }

    @Test func timeoutIncludesAChildThatNeverReadsStdin() {
        let began = ContinuousClock.now
        let result = BoundedSubprocess.run("/bin/sleep", ["3"], input: Data(repeating: 65, count: 2 * 1024 * 1024), timeout: 0.1)
        #expect(result.status == 124)
        #expect(result.error.contains("timed out"))
        #expect(began.duration(to: .now) < .seconds(1.5))
    }

    @Test func ignoresTermIsKilledAndNeverReportedAsSuccess() throws {
        let began = ContinuousClock.now
        let result = BoundedSubprocess.run("/bin/sh", ["-c", "trap '' TERM; echo $$; exec /bin/sleep 3"], timeout: 0.15)
        #expect(result.status == 124)
        let pid = try #require(Int32(result.output.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        #expect(began.duration(to: .now) < .seconds(1.5))
    }

    @Test func outputBudgetStopsANoisyChildWithoutRetainingTheExcess() {
        let result = BoundedSubprocess.run("/bin/sh", ["-c", "exec /bin/dd if=/dev/zero bs=65536 count=200"],
                                           timeout: 2, maxOutputBytes: 32_768)
        #expect(result.status == 125)
        #expect(result.error.contains("byte limit"))
        #expect(result.output.utf8.count <= 32_768)
    }

    @Test func earlyInputCloseCannotSignalTheParentOrClaimACompletedRequest() {
        let result = BoundedSubprocess.run("/bin/sh", ["-c", "exec 0<&-; sleep 0.1"],
                                           input: Data(repeating: 65, count: 2 * 1024 * 1024), timeout: 1)
        #expect(result.status != 0)
        #expect(result.error.contains("input"))
        // Reaching this assertion proves a closed child pipe did not deliver fatal SIGPIPE.
    }

    @Test func inheritedOutputDescriptorCannotKeepCallerWaitingForEOF() {
        let began = ContinuousClock.now
        let result = BoundedSubprocess.run("/bin/sh", ["-c", "sleep 3 & exit 0"], timeout: 0.1)
        #expect(result.status == 124)
        // Includes the separately bounded 250 ms termination grace and one-second reap window.
        #expect(began.duration(to: .now) < .seconds(2))
    }

    @Test func emptyInputDeliversEOFAndConcurrentHelpersDoNotRetainEachOthersPipes() async {
        let results = await withTaskGroup(of: BoundedSubprocess.Result.self) { group in
            for _ in 0..<8 {
                group.addTask { BoundedSubprocess.run("/bin/sh", ["-c", "cat; printf done"], timeout: 2) }
            }
            var results: [BoundedSubprocess.Result] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 8)
        #expect(results.allSatisfy { $0.status == 0 && $0.output == "done" && $0.error.isEmpty })
    }

    @Test func invalidLimitsAndMissingExecutableFailBeforeAnySuccess() {
        #expect(BoundedSubprocess.run("/bin/true", [], timeout: .infinity).status == 125)
        #expect(BoundedSubprocess.run("/bin/true", [], timeout: 0).status == 125)
        #expect(BoundedSubprocess.run("/bin/true", [], maxOutputBytes: 0).status == 125)
        #expect(BoundedSubprocess.run("/zeus-test-does-not-exist", []).status == 126)
    }
}
