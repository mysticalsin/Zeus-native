import Foundation
import Testing
@testable import Zeus

/// A zero-width space stays in a CLI version line. These tests name the blanks.
/// Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("CLI version line box")
struct CLIVersionLineBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(CLIVersionLineBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(CLIVersionLineBox.blankScalars.count == 5)
        #expect(CLIVersionLineBox.blankScalars.contains(" "))
        #expect(CLIVersionLineBox.blankScalars.contains("\t"))
        #expect(CLIVersionLineBox.blankScalars.contains("\n"))
        #expect(CLIVersionLineBox.blankScalars.contains("\r"))
        #expect(CLIVersionLineBox.blankScalars.contains("\u{00A0}"))
        #expect(!CLIVersionLineBox.blankScalars.contains("\u{200B}"))
        #expect(!CLIVersionLineBox.blankScalars.contains("\u{000B}"))
        #expect(!CLIVersionLineBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedLine() {
        #expect(CLIVersionLineBox.trimmedLine("\u{200B}") == "\u{200B}")
        #expect(CLIVersionLineBox.trimmedLine(" \u{200B} ") == "\u{200B}")
        #expect(CLIVersionLineBox.trimmedLine("\t\u{200B}\n") == "\u{200B}")
        #expect(CLIVersionLineBox.trimmedLine("\u{200B}1.0") == "\u{200B}1.0")
        #expect(CLIVersionLineBox.trimmedLine("1.0\u{200B}") == "1.0\u{200B}")
        #expect(CLIVersionLineBox.trimmedLine(" \t\n\r\u{00A0}") == "")
        #expect(CLIVersionLineBox.trimmedLine("") == "")
        #expect(CLIVersionLineBox.trimmedLine("\u{000B}1.0") == "\u{000B}1.0")
        #expect(CLIVersionLineBox.trimmedLine("\u{3000}1.0") == "\u{3000}1.0")
        #expect(CLIVersionLineBox.trimmedLine(" \t1.0\r\n") == "1.0")
        #expect(CLIVersionLineBox.trimmedLine("\u{00A0}1.0\u{00A0}") == "1.0")
        #expect(CLIVersionLineBox.trimmedLine("1.0") == "1.0")
    }

    @Test func aZeroWidthSpaceStaysInTheVersionLine() async throws {
        let kept = await CLILocator.version(at: tool("printf '\\342\\200\\213\\n'"))
        #expect(kept == "\u{200B}")
        let padded = await CLILocator.version(at: tool("printf ' \\342\\200\\213 \\n'"))
        #expect(padded == "\u{200B}")
        let blanks = await CLILocator.version(at: tool("printf ' \\t\\n'"))
        #expect(blanks == "")
        let ideograph = await CLILocator.version(at: tool("printf '\\343\\200\\2001.0\\n'"))
        #expect(ideograph == "\u{3000}1.0")
        let nobreak = await CLILocator.version(at: tool("printf '\\302\\2401.0\\302\\240\\n'"))
        #expect(nobreak == "1.0")
        let failed = await CLILocator.version(at: tool("printf '\\342\\200\\213\\n'\nexit 1"))
        #expect(failed == nil)
    }
}

private func tool(_ body: String) -> String {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cli-version-\(UUID().uuidString)")
    let script = "#!/bin/sh\n" + body + "\n"
    try? Data(script.utf8).write(to: url)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}
