import Foundation
import Testing

/// The macOS Automation prompt shows this text, so it has to name every app Zeus addresses by name in an
/// AppleScript `tell application "..."` (found by reading the sources) plus the music players it scripts by bundle id.
@Suite("Automation usage description")
struct AutomationUsageStringTests {
    private func plist() throws -> [String: Any] {
        // Tests/ZeusCoreTests/<this file> -> repository root -> Resources/Info.plist
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theAppleEventsStringNamesTheTerminalAndITermScripting() throws {
        let text = try #require(try plist()["NSAppleEventsUsageDescription"] as? String)
        for name in ["Chrome", "Music", "Spotify", "Terminal", "iTerm"] {
            #expect(text.contains(name), "\(name) is scripted but not named")
        }
        #expect(text.contains("type"), "it should say Zeus types into a shell")
    }

    @Test func theStringNamesEveryAppTheSourcesScriptByName() throws {
        let text = try #require(try plist()["NSAppleEventsUsageDescription"] as? String)
        let targets = try scriptedApplicationNames()
        #expect(targets.isSuperset(of: ["Terminal", "iTerm2", "Keynote", "Microsoft PowerPoint", "System Events"]), "the scan found \(targets)")
        for target in targets {
            // "iTerm2" is covered by "iTerm", "Microsoft PowerPoint" by "PowerPoint".
            let short = target.hasPrefix("Microsoft ") ? String(target.dropFirst("Microsoft ".count)) : target.replacingOccurrences(of: "2", with: "")
            #expect(text.contains(short), "\(target) is scripted but not named")
        }
    }

    private func scriptedApplicationNames() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let expression = try NSRegularExpression(pattern: #"tell application \\?"([^"\\]+)\\?""#)
        var found = Set<String>()
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..., in: source)
            for match in expression.matches(in: source, range: range) {
                if let name = Range(match.range(at: 1), in: source) { found.insert(String(source[name])) }
            }
        }
        return found
    }

    @Test func theSystemEventsClauseNamesBeamerNotAPresentationTool() throws {
        let text = try #require(try plist()["NSAppleEventsUsageDescription"] as? String)
        #expect(text.contains("Beamer"), "the only System Events script drives the Beamer menu")
        #expect(!text.contains("presentation tool"), "Beamer shares a keyboard and mouse, it is not a presentation tool")
    }

    @Test func theStringKeepsToTheHouseWritingRules() throws {
        let text = try #require(try plist()["NSAppleEventsUsageDescription"] as? String)
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "no em or en dashes")
        #expect(text.count < 600)
    }
}
