import Foundation
import Testing

/// The reply path types into another app. These checks read the hub source because the app target
/// does not build on Linux. They fail while Send still runs a script from the same call that asks.
@Suite("Reply wiring")
struct HubReplyWiringTests {
    private static let source: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zeus/Agents/AgentHub.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    @Test func sendDoesNotRunAScriptOrAskOnACard() throws {
        let source = try #require(Self.loadedSource)
        let send = try #require(Self.functionBody("sendReply", in: source))
        #expect(!send.contains(".send("))
        #expect(!send.contains("NSAppleScript"))
        #expect(!send.contains("typeApprovedLine"))
        #expect(!send.contains("runGuardedScript"))
        #expect(!send.contains("requestApproval"))
        #expect(!source.contains("requestApproval"))
        #expect(!source.contains("autoApproves"))
    }

    @Test func keystrokesAreGuardedAndTrustCannotSkipTheApproval() throws {
        let source = try #require(Self.loadedSource)
        let type = try #require(Self.functionBody("typeApprovedLine", in: source))
        let run = try #require(Self.functionBody("runGuardedScript", in: source))
        #expect(type.contains("mayRun"))
        #expect(type.contains("runGuardedScript"))
        let mayRun = try #require(type.range(of: "mayRun"))
        let runCall = try #require(type.range(of: "runGuardedScript"))
        #expect(mayRun.lowerBound < runCall.lowerBound)
        #expect(run.contains("NSAppleScript"))
        #expect(!source.contains("if trusted"))
        #expect(!source.contains("guard trusted"))
        #expect(!source.contains("trusted ?"))
        let approve = try #require(Self.functionBody("approveReply", in: source))
        #expect(approve.contains("typeApprovedLine"))
        #expect(!approve.contains("NSAppleScript"))
    }

    private static var loadedSource: String? {
        source.isEmpty ? nil : source
    }

    /// The body of one function, from its opening brace through the matching close.
    static func functionBody(_ name: String, in source: String) -> String? {
        guard let signature = source.range(of: "func \(name)") else { return nil }
        guard let open = source[signature.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
