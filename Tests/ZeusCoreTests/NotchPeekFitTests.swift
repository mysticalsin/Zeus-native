import Foundation
import Testing
@testable import ZeusCore

/// The peek bar has to hold the scaled title. The closed bar stays on its 30 pt floor at the standard size.
@Suite struct NotchPeekFitTests {
    @Test func accessibilitySizeFitsAndTheClosedBarStays() throws {
        #expect(NotchPeekFit.barHeight(notchHeight: 20, scaledFont: 12, peeking: false) == 30)
        #expect(NotchPeekFit.barHeight(notchHeight: 20, scaledFont: 12, peeking: true) == 30)
        #expect(NotchPeekFit.barHeight(notchHeight: 36, scaledFont: 32.4, peeking: false) == 36)
        #expect(NotchPeekFit.barHeight(notchHeight: 20, scaledFont: 32.4, peeking: true) >= 32.4)
        let notch = try repoSource("Sources/Zeus/Notch/NotchView.swift")
        #expect(notch.contains("NotchPeekFit.barHeight"))
        #expect(notch.contains("minimumScaleFactor") || notch.contains("lineLimit(2)"))
    }

    private func repoSource(_ relative: String) throws -> String {
        if let root = ProcessInfo.processInfo.environment["ZEUS_REPO"], !root.isEmpty {
            return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(relative), encoding: .utf8)
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        Issue.record("Missing \(relative)")
        return ""
    }
}
