import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// A zero-width space stays on an admin-step failure detail. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Insomnia failure detail box")
struct InsomniaFailureDetailBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(InsomniaFailureDetailBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(InsomniaFailureDetailBox.blankScalars.count == 5)
        #expect(InsomniaFailureDetailBox.blankScalars.contains(" "))
        #expect(InsomniaFailureDetailBox.blankScalars.contains("\t"))
        #expect(InsomniaFailureDetailBox.blankScalars.contains("\n"))
        #expect(InsomniaFailureDetailBox.blankScalars.contains("\r"))
        #expect(InsomniaFailureDetailBox.blankScalars.contains("\u{00A0}"))
        #expect(!InsomniaFailureDetailBox.blankScalars.contains("\u{200B}"))
        #expect(!InsomniaFailureDetailBox.blankScalars.contains("\u{000B}"))
        #expect(!InsomniaFailureDetailBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedFailure() {
        #expect(InsomniaFailureDetailBox.trimmedFailure("\u{200B}") == "\u{200B}")
        #expect(InsomniaFailureDetailBox.trimmedFailure(" \u{200B} ") == "\u{200B}")
        #expect(InsomniaFailureDetailBox.trimmedFailure("\t\u{200B}\n") == "\u{200B}")
        #expect(InsomniaFailureDetailBox.trimmedFailure("\u{200B}denied") == "\u{200B}denied")
        #expect(InsomniaFailureDetailBox.trimmedFailure("denied\u{200B}") == "denied\u{200B}")
        #expect(InsomniaFailureDetailBox.trimmedFailure(" \t\n\r\u{00A0}") == "")
        #expect(InsomniaFailureDetailBox.trimmedFailure("") == "")
        #expect(InsomniaFailureDetailBox.trimmedFailure("\u{000B}denied") == "\u{000B}denied")
        #expect(InsomniaFailureDetailBox.trimmedFailure("\u{3000}denied") == "\u{3000}denied")
        #expect(InsomniaFailureDetailBox.trimmedFailure(" \tdenied\r\n") == "denied")
        #expect(InsomniaFailureDetailBox.trimmedFailure("\u{00A0}denied\u{00A0}") == "denied")
        #expect(InsomniaFailureDetailBox.trimmedFailure("denied") == "denied")
    }

    @Test func aZeroWidthSpaceStaysOnTheAdminStepFailure() {
        #expect(uninstall("\u{200B}") == .failed("\u{200B}"))
        #expect(uninstall(" \u{200B} ") == .failed("\u{200B}"))
        #expect(uninstall("\t\u{200B}\n") == .failed("\u{200B}"))
        #expect(uninstall("\u{200B}denied") == .failed("\u{200B}denied"))
        #expect(uninstall("denied\u{200B}") == .failed("denied\u{200B}"))
        #expect(uninstall("\u{3000}denied") == .failed("\u{3000}denied"))
        #expect(uninstall("\u{000B}denied") == .failed("\u{000B}denied"))
        #expect(uninstall(" \t\n\r\u{00A0}") == .failed("The admin step failed (exit 1)."))
        #expect(uninstall("") == .failed("The admin step failed (exit 1)."))
        #expect(uninstall(" \tdenied\r\n") == .failed("denied"))
        #expect(uninstall("\u{00A0}denied\u{00A0}") == .failed("denied"))
        #expect(uninstall("denied") == .failed("denied"))
        #expect(uninstall("no", ok: true) == .done("Removed. The Mac sleeps with the lid closed again."))
        #expect(uninstall("execution error: User canceled. (-128)") == .cancelled)
    }
}

private struct FixedRunner: InsomniaCommandRunner {
    var result: InsomniaCommandResult
    func run(_ executable: String, _ arguments: [String]) -> InsomniaCommandResult { result }
}

private func uninstall(_ stderr: String, ok: Bool = false) -> InsomniaInstaller.Outcome {
    let installer = InsomniaInstaller(
        runner: FixedRunner(result: InsomniaCommandResult(status: ok ? 0 : 1, stderr: stderr)),
        user: "tony",
        uid: 501,
        home: URL(fileURLWithPath: "/home/tony"),
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        cliPath: "/usr/local/bin/zeus",
        logPath: "/tmp/insomnia-guard.log",
        fileExists: { _ in true }
    )
    return installer.uninstall()
}
