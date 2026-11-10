import AppKit
import ApplicationServices
import ZeusCore

/// "Play <X> on Spotify" with no Spotify API setup: open `spotify:search:<X>`, wait for the window,
/// then use the Accessibility API to press the play button of the top result (or the first track).
/// Spotify is a Chromium (CEF) app, so its tree is built only after `AXManualAccessibility` /
/// `AXEnhancedUserInterface` is set on the app element. If no control turns up within the budget,
/// Spotify is left on the search results and the caller says so. The AppleScript `play` fallback
/// runs only when Automation is already allowed, and is kept only if the track that starts
/// matches the search (otherwise it is paused again): it resumes the old queue, not the search.
enum SpotifyPlayer {
    static let bundleID = "com.spotify.client"

    enum Outcome: Equatable {
        /// Pressed a play control through Accessibility; `verified` when playback was seen to start.
        case accessibility(label: String, verified: Bool)
        case appleScript(track: String)
        /// Spotify shows the search; nothing was pressed. `reason` is for the log.
        case shownOnly(reason: String)
        case notInstalled
    }

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    static func searchURL(_ query: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "spotify:search:" + encoded)
    }

    /// Opens the search at once (the "action started" moment), then finds and presses play.
    @MainActor
    static func play(_ query: String, started: () -> Void, isPlaying: @escaping @MainActor () -> Bool?) async -> Outcome {
        guard isInstalled, let url = searchURL(query) else { return .notInstalled }
        let began = Date()
        NSWorkspace.shared.open(url)
        started()

        // Wait for the app (a cold launch takes a few seconds), then give the search 2.5 s to render.
        var app: NSRunningApplication?
        for _ in 0..<80 {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            if app?.isFinishedLaunching == true { break }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return .shownOnly(reason: "cancelled") }
        }
        guard let app else { return log(.shownOnly(reason: "Spotify did not start within 8 s"), began) }
        guard AXIsProcessTrusted() else {
            return log(await appleScriptFallback(query, reason: "no Accessibility access"), began)
        }
        let pid = app.processIdentifier
        let tokens = Self.tokens(query)
        let found = await Task.detached(priority: .userInitiated) { () -> (String, String)? in
            let finder = SpotifyAXFinder(pid: pid, queryTokens: tokens)
            return finder.findAndPress(budget: 2.5)
        }.value
        guard let (label, how) = found else {
            return log(await appleScriptFallback(query, reason: "no play control found in 2.5 s"), began)
        }
        NSLog("[ZEUS] spotify: pressed \"%@\" (%@)", label, how)
        // Spotify posts its playback notification within a moment when it starts.
        var verified = false
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            if isPlaying() == true { verified = true; break }
        }
        return log(.accessibility(label: label, verified: verified), began)
    }

    private static func log(_ outcome: Outcome, _ began: Date) -> Outcome {
        NSLog("[ZEUS] spotify: %@ after %.0fms", String(describing: outcome), Date().timeIntervalSince(began) * 1000)
        return outcome
    }

    static func tokens(_ query: String) -> [String] {
        AppMatcher.normalize(query).split(separator: " ").map(String.init).filter { $0.count > 2 }
    }

    /// AppleScript `play` resumes Spotify's current context, which a search URL does not change.
    /// Keep it only when the track that starts matches the search; otherwise pause it again.
    @MainActor
    private static func appleScriptFallback(_ query: String, reason: String) async -> Outcome {
        guard Automation.allowed(bundleID) else { return .shownOnly(reason: reason + "; Automation for Spotify not allowed") }
        let wasPlaying = await osascript("tell application id \"\(bundleID)\" to player state as string") == "playing"
        _ = await osascript("tell application id \"\(bundleID)\" to play")
        try? await Task.sleep(for: .milliseconds(900))
        let track = await osascript("tell application id \"\(bundleID)\" to (name of current track) & \" by \" & (artist of current track)") ?? ""
        let haystack = AppMatcher.normalize(track)
        let tokens = Self.tokens(query)
        if !tokens.isEmpty, tokens.contains(where: { haystack.contains($0) }) { return .appleScript(track: track) }
        if !wasPlaying { _ = await osascript("tell application id \"\(bundleID)\" to pause") }
        return .shownOnly(reason: reason + "; AppleScript play resumed \"\(track)\", not the search, so it was undone")
    }

    /// Runs one AppleScript line out of process, off the main thread. nil on failure.
    static func osascript(_ source: String) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            // A hung player never answers: give up after 3 s instead of waiting forever.
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning, Date() < deadline { usleep(20_000) }
            if process.isRunning { process.terminate(); return nil }
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

/// Walks Spotify's AX tree for the search page's play control. Runs off the main thread; every
/// AX call is IPC, so it fetches several attributes per node in one call and skips the sidebar.
struct SpotifyAXFinder: Sendable {
    let pid: pid_t
    let queryTokens: [String]

    static let playWords = ["play", "tocar", "reproduzir", "lire", "écouter", "ecouter", "reproducir", "lecture"]
    static let topResultLabels = ["top result", "melhor resultado", "meilleur résultat", "meilleur resultat", "mejor resultado"]

    struct Node {
        let element: AXUIElement
        let role: String
        let subrole: String
        let label: String
        let children: [AXUIElement]
    }

    /// Returns the pressed control's label and how it was chosen, or nil.
    func findAndPress(budget: TimeInterval) -> (String, String)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        // Chromium builds its accessibility tree only for assistive clients that ask.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        let deadline = Date().addingTimeInterval(budget)
        var attempts = 0
        var lastReason = "no window"
        while Date() < deadline {
            attempts += 1
            if let window = windows(app).first {
                switch choose(in: window, deadline: deadline) {
                case .success(let pick):
                    if AXUIElementPerformAction(pick.element, kAXPressAction as CFString) == .success {
                        return (pick.label, pick.how + ", attempt \(attempts)")
                    }
                    lastReason = "press failed on \"\(pick.label)\""
                case .failure(let reason):
                    lastReason = reason.text
                }
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        NSLog("[ZEUS] spotify: AX search gave up after %d tries: %@", attempts, lastReason)
        return nil
    }

    struct Pick { let element: AXUIElement; let label: String; let how: String }
    struct Reason: Error { let text: String }

    private func choose(in window: AXUIElement, deadline: Date) -> Result<Pick, Reason> {
        // 1. Find the main content landmark (breadth first, shallow), so the Library sidebar's
        //    "Play <playlist>" buttons and the player bar's "Play" are never candidates.
        let main = findMain(window, deadline: deadline) ?? window
        // 2. Document order inside it: the "Top result" heading, then play buttons with a name.
        var order: [(Node, Int)] = []
        var stack: [(AXUIElement, Int)] = [(main, 0)]
        var visited = 0
        while let (element, depth) = stack.popLast() {
            visited += 1
            if visited > 4_000 || Date() > deadline { break }
            guard let node = read(element) else { continue }
            if node.subrole == "AXLandmarkNavigation" || node.subrole == "AXLandmarkComplementary" { continue }
            order.append((node, depth))
            if depth < 60 { stack += node.children.reversed().map { ($0, depth + 1) } }
        }
        let headingIndex = order.firstIndex { node, _ in
            let text = node.label.lowercased()
            return Self.topResultLabels.contains { text == $0 }
        }
        let candidates = order.enumerated().compactMap { index, entry -> (Int, Node)? in
            let (node, _) = entry
            guard node.role == "AXButton", Self.playTarget(node.label) != nil else { return nil }
            return (index, node)
        }
        if candidates.isEmpty { return .failure(Reason(text: "no named play buttons yet (\(order.count) nodes, main \(CFEqual(main, window) ? "not found" : "found"))")) }
        if let heading = headingIndex, let pick = candidates.first(where: { $0.0 > heading }) {
            return .success(Pick(element: pick.1.element, label: pick.1.label, how: "after Top result"))
        }
        if let pick = candidates.first(where: { candidate in
            let label = AppMatcher.normalize(candidate.1.label)
            return queryTokens.contains { label.contains($0) }
        }) {
            return .success(Pick(element: pick.1.element, label: pick.1.label, how: "label matches the search"))
        }
        let first = candidates[0].1
        return .success(Pick(element: first.element, label: first.label, how: "first named play button"))
    }

    /// "Play Daft Punk" → "Daft Punk". Bare "Play" / "Pause" (the player bar) → nil.
    static func playTarget(_ label: String) -> String? {
        let lower = label.lowercased()
        for word in playWords where lower.hasPrefix(word + " ") {
            let rest = label.dropFirst(word.count + 1).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty || rest.hasPrefix("(") { return nil }
            return rest
        }
        return nil
    }

    private func findMain(_ root: AXUIElement, deadline: Date) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var head = 0
        while head < queue.count, head < 1_500, Date() < deadline {
            let (element, depth) = queue[head]
            head += 1
            guard let node = read(element) else { continue }
            if node.subrole == "AXLandmarkMain" { return element }
            if depth < 18 { queue += node.children.map { ($0, depth + 1) } }
        }
        return nil
    }

    private func windows(_ app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// Role, subrole, title, description, value and children in one IPC call.
    private func read(_ element: AXUIElement) -> Node? {
        let names = ["AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue", "AXChildren"] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let list = values as? [Any], list.count == 6 else { return nil }
        func text(_ i: Int) -> String { (list[i] as? String) ?? "" }
        let label = [text(2), text(3), text(4)].first { !$0.isEmpty } ?? ""
        return Node(element: element, role: text(0), subrole: text(1), label: label, children: list[5] as? [AXUIElement] ?? [])
    }
}
