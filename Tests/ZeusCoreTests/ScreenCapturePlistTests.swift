import Foundation
import Testing

/// S04-05. Screen capture is called, and the purpose string the system shows was missing.
@Suite("Screen capture purpose string")
struct ScreenCapturePlistTests {
    static let purpose = "ZEUS captures the screen when you talk with screen consent on, when desktop pointing places a mark, when you record, and for live captions of the sound this Mac is playing. A screenshot is kept only while you are recording."

    private func plist() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let manifest = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                let data = try Data(contentsOf: url.appendingPathComponent("Resources/Info.plist"))
                return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        return [:]
    }

    @Test func infoPlistStatesWhyTheScreenIsCaptured() throws {
        let text = try #require(try plist()["NSScreenCaptureUsageDescription"] as? String)
        #expect(text == Self.purpose)
    }
}
