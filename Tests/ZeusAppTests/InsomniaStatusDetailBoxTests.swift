import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// A zero-width space stays on a sudo status detail. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Insomnia status detail box")
struct InsomniaStatusDetailBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(InsomniaStatusDetailBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(InsomniaStatusDetailBox.blankScalars.count == 5)
        #expect(InsomniaStatusDetailBox.blankScalars.contains(" "))
        #expect(InsomniaStatusDetailBox.blankScalars.contains("\t"))
        #expect(InsomniaStatusDetailBox.blankScalars.contains("\n"))
        #expect(InsomniaStatusDetailBox.blankScalars.contains("\r"))
        #expect(InsomniaStatusDetailBox.blankScalars.contains("\u{00A0}"))
        #expect(!InsomniaStatusDetailBox.blankScalars.contains("\u{200B}"))
        #expect(!InsomniaStatusDetailBox.blankScalars.contains("\u{000B}"))
        #expect(!InsomniaStatusDetailBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedDetail() {
        #expect(InsomniaStatusDetailBox.trimmedDetail("\u{200B}") == "\u{200B}")
        #expect(InsomniaStatusDetailBox.trimmedDetail(" \u{200B} ") == "\u{200B}")
        #expect(InsomniaStatusDetailBox.trimmedDetail("\t\u{200B}\n") == "\u{200B}")
        #expect(InsomniaStatusDetailBox.trimmedDetail("\u{200B}denied") == "\u{200B}denied")
        #expect(InsomniaStatusDetailBox.trimmedDetail("denied\u{200B}") == "denied\u{200B}")
        #expect(InsomniaStatusDetailBox.trimmedDetail(" \t\n\r\u{00A0}") == "")
        #expect(InsomniaStatusDetailBox.trimmedDetail("") == "")
        #expect(InsomniaStatusDetailBox.trimmedDetail("\u{000B}denied") == "\u{000B}denied")
        #expect(InsomniaStatusDetailBox.trimmedDetail("\u{3000}denied") == "\u{3000}denied")
        #expect(InsomniaStatusDetailBox.trimmedDetail(" \tdenied\r\n") == "denied")
        #expect(InsomniaStatusDetailBox.trimmedDetail("\u{00A0}denied\u{00A0}") == "denied")
        #expect(InsomniaStatusDetailBox.trimmedDetail("denied") == "denied")
    }

    @Test func aZeroWidthSpaceStaysOnTheSudoStatus() {
        #expect(status("\u{200B}") == .needsRepair("\u{200B}"))
        #expect(status(" \u{200B} ") == .needsRepair("\u{200B}"))
        #expect(status("\t\u{200B}\n") == .needsRepair("\u{200B}"))
        #expect(status("\u{200B}denied") == .needsRepair("\u{200B}denied"))
        #expect(status("denied\u{200B}") == .needsRepair("denied\u{200B}"))
        #expect(status("\u{3000}denied") == .needsRepair("\u{3000}denied"))
        #expect(status("\u{000B}denied") == .needsRepair("\u{000B}denied"))
        #expect(status(" \t\n\r\u{00A0}") == .needsRepair("sudo said no"))
        #expect(status("") == .needsRepair("sudo said no"))
        #expect(status(" \tdenied\r\n") == .needsRepair("denied"))
        #expect(status("\u{00A0}denied\u{00A0}") == .needsRepair("denied"))
        #expect(status("denied") == .needsRepair("denied"))
        #expect(status("no", ok: true) == .installed)
        #expect(status("\u{200B}", exists: false) == .notInstalled)
    }
}

private struct FixedRunner: InsomniaCommandRunner {
    var result: InsomniaCommandResult
    func run(_ executable: String, _ arguments: [String]) -> InsomniaCommandResult { result }
}

private func status(_ stderr: String, ok: Bool = false, exists: Bool = true) -> InsomniaInstaller.Status {
    let installer = InsomniaInstaller(
        runner: FixedRunner(result: InsomniaCommandResult(status: ok ? 0 : 1, stderr: stderr)),
        user: "tony",
        uid: 501,
        home: URL(fileURLWithPath: "/home/tony"),
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        cliPath: "/usr/local/bin/zeus",
        logPath: "/tmp/insomnia-guard.log",
        fileExists: { _ in exists }
    )
    return installer.status()
}
