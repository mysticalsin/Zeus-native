import Foundation

/// Atticus parity O0: Zeus is a clean-room build from the behavior spec only.
public enum AtticusCleanRoom {
    /// Private SkyLight background-event APIs and banned product integrations (O0).
    public static let forbiddenSourceTokens: [String] = [
        "SLEventPostToPid",
        "SLEventSetAuthenticationMessage",
        "PostHog",
        "posthog",
        "Gumroad",
        "gumroad",
    ]

    /// Atticus code is not compiled in; do not claim it in NOTICES unless a snippet is ever reused.
    public static let forbiddenNoticesTokens: [String] = [
        "atticus-mac",
        "SaarthurR/atticus",
        "github.com/SaarthurR/atticus",
    ]

    /// Clean-room parity copy: behavior notes only, no banned vendor or private API names.
    public static let sampleAtticusParityStrings: [String] = [
        "Zeus follows the Atticus behavior spec only; no Atticus source is compiled in.",
        "Skip third-party analytics capture, paid license stubs, and tip prompts from the reference app.",
        "Inject input with public CGEvent.postToPid and accessibility APIs, not private SkyLight event posts.",
        "On-device speech shows live partial words and clears them when the user revises.",
        "Learned shortcuts replay stored steps locally with no cloud model call.",
    ]

    public static func forbiddenHits(in text: String) -> [String] {
        forbiddenSourceTokens.filter { text.contains($0) }
    }

    public static func noticesViolations(_ notices: String) -> [String] {
        forbiddenNoticesTokens.filter { notices.localizedCaseInsensitiveContains($0) }
    }

    public static func scanSwiftFiles(under root: URL) -> [String] {
        var problems: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return ["scan failed"] }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            if url.lastPathComponent == "AtticusCleanRoom.swift" { continue }
            guard let data = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for token in forbiddenHits(in: data) {
                problems.append("\(url.lastPathComponent):\(token)")
            }
        }
        return problems
    }

    public static func report(notices: String, sourceRoot: URL?) -> (text: String, passed: Bool) {
        var problems: [String] = []
        let noticeHits = noticesViolations(notices)
        if !noticeHits.isEmpty { problems.append("notices=\(noticeHits.joined(separator: ","))") }
        if let sourceRoot {
            let hits = scanSwiftFiles(under: sourceRoot)
            if !hits.isEmpty { problems.append("sources=\(hits.prefix(5).joined(separator: ";"))") }
        }
        let text = problems.isEmpty
            ? "PASS clean-room notices=ok sources=ok"
            : "FAIL \(problems.joined(separator: " "))"
        return (text, problems.isEmpty)
    }
}
