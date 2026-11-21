import Foundation
import Testing

/// S04-05. Screen capture is called, and the purpose string the system shows was missing.
@Suite("Screen capture purpose string")
struct ScreenCapturePlistTests {
    static let purpose = "ZEUS captures the screen when you talk with screen consent on, when desktop pointing places a mark, when you record, and for live captions of the sound this Mac is playing. Screenshots go to the assistant engine you chose and are not kept as files. A screen recording is saved on this Mac and stays after you stop."

    private func plistFile() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let manifest = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return url.appendingPathComponent("Resources/Info.plist")
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        throw CocoaError(.fileReadNoSuchFile)
    }

    private func plist() throws -> [String: Any] {
        let data = try Data(contentsOf: try plistFile())
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func infoPlistStatesWhyTheScreenIsCaptured() throws {
        let file = try plistFile()
        let text = try #require(try plist()["NSScreenCaptureUsageDescription"] as? String)
        #expect(text == Self.purpose)
        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(raw.components(separatedBy: "<key>NSScreenCaptureUsageDescription</key>").count - 1 == 1)
    }
}
