import Foundation
import Testing
@testable import ZeusCore

/// Regression for the debug-hook merge conflicts.
/// At b8a3b06 each lane edited the unknown-command sentence, so keeping one side
/// dropped the other lane's hooks. At 536a698 lane F still had that handwritten
/// sentence (it named brain-route and omitted hands, learn and selection) while
/// the catalog omitted brain-route. The switch, the help line and the unknown
/// reply all have to come from this one list.
@Suite struct DebugSubcommandCatalogTests {
    /// Hooks that existed on only one side of those conflicts, plus `present-timeline`,
    /// which the switch already handled and neither help line named.
    private static let droppedByEitherSide = [
        "present", "present-timeline", "wake-false-triggers", "hands", "hands-live", "learn", "selection",
        "clean-room", "on-device-speech", "permissions",
        "hud-state", "update", "screen-share", "engine-logos", "import-assistant-key",
        "brain-route",
    ]

    @Test func helpAndUnknownReplyUseTheSameList() {
        let names = DebugSubcommandCatalog.names
        #expect(Set(names).count == names.count)
        for name in Self.droppedByEitherSide {
            #expect(names.contains(name))
        }

        let usage = ZeusCLI.usage
        #expect(usage.components(separatedBy: "internal test hooks (").count == 2)
        guard let start = usage.range(of: "internal test hooks ("),
              let end = usage[start.upperBound...].range(of: ")") else {
            Issue.record("debug help line missing")
            return
        }
        let listed = usage[start.upperBound..<end.lowerBound].split(separator: ", ").map(String.init)
        #expect(listed == names)

        let reply = DebugSubcommandCatalog.unknownMessage("nope")
        #expect(reply == "Unknown debug subcommand: nope. Use \(DebugSubcommandCatalog.list).")
        for name in names {
            #expect(reply.contains(name))
        }
    }

    @Test func catalogMatchesTheDebugSwitch() throws {
        let source = try String(contentsOf: commandCenterURL(), encoding: .utf8)
        #expect(debugSwitchCases(source) == DebugSubcommandCatalog.names)
        #expect(source.contains("DebugSubcommandCatalog.unknownMessage"))
        #expect(!source.contains("Use open-settings"))
    }
}

private func commandCenterURL() throws -> URL {
    var url = URL(fileURLWithPath: #filePath)
    let files = FileManager.default
    while url.path != "/" {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent("Sources/Zeus/App/CommandCenter.swift")
        if files.fileExists(atPath: candidate.path) { return candidate }
    }
    throw CocoaError(.fileNoSuchFile)
}

private func debugSwitchCases(_ source: String) -> [String] {
    guard let marker = source.range(of: "switch subcommand {") else { return [] }
    let rest = source[marker.upperBound...]
    guard let end = rest.range(of: "\n            default:") else { return [] }
    let body = rest[..<end.lowerBound]
    var names: [String] = []
    var search = body.startIndex
    let token = "case \""
    while let found = body[search...].range(of: token) {
        let nameStart = found.upperBound
        guard let nameEnd = body[nameStart...].firstIndex(of: "\"") else { break }
        names.append(String(body[nameStart..<nameEnd]))
        search = body.index(after: nameEnd)
    }
    return names
}
