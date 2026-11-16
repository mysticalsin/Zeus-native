import Foundation
import Testing

/// Source rules that keep motion smooth: no fast run-loop timers for visible motion, no animation that fires for
/// every change, and no spring numbers outside the token table (`MotionTokens`). The rules are plain functions of
/// the source text, so they are tested on small fixtures as well as on the real tree.
@Suite("Motion source lint")
struct MotionSourceLintTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Zeus")

    // MARK: Rules

    /// Source with `//` comments blanked, so rules do not read prose.
    static func code(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard let range = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<range.lowerBound])
        }.joined(separator: "\n")
    }

    /// The text of the parenthesised group that opens at `open` (exclusive of the parentheses).
    static func group(in text: String, opening open: String.Index) -> String {
        var depth = 0
        var index = open
        let start = text.index(after: open)
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" { depth -= 1; if depth == 0 { return String(text[start..<index]) } }
            index = text.index(after: index)
        }
        return String(text[start...])
    }

    /// Every number or quotient written in an expression: `0.5`, `1 / 30`, `1.0 / 24.0`.
    static func numbers(in expression: String) -> [Double] {
        let pattern = #"(\d+(?:\.\d+)?)(?:\s*/\s*(\d+(?:\.\d+)?))?"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = expression as NSString
        return regex.matches(in: expression, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let top = Double(ns.substring(with: match.range(at: 1))) else { return nil }
            if match.range(at: 2).location != NSNotFound, let bottom = Double(ns.substring(with: match.range(at: 2))), bottom != 0 {
                return top / bottom
            }
            return top
        }
    }

    /// Visible motion must not run on a run-loop clock faster than 0.1 s: `TickingView(interval:)`, and
    /// `TimelineView(.animation(minimumInterval:))` or `.periodic(by:)`.
    static func fastClocks(in source: String) -> [String] {
        let text = code(source)
        var found: [String] = []
        for (opener, label) in [("TickingView(", "interval:"), ("TimelineView(", "minimumInterval:"), ("TimelineView(", "by:")] {
            var from = text.startIndex
            while let range = text.range(of: opener, range: from..<text.endIndex) {
                from = range.upperBound
                let open = text.index(before: range.upperBound)
                let args = group(in: text, opening: open)
                guard let labelRange = args.range(of: label) else { continue }
                var expression = String(args[labelRange.upperBound...])
                if let end = expression.firstIndex(where: { $0 == "," || $0 == "{" }) { expression = String(expression[..<end]) }
                if let small = numbers(in: expression).min(), small < 0.1 {
                    found.append("\(opener)\(label)\(expression.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return found
    }

    /// `.animation(` with no `value:` is allowed only inside a `.transition(...)` call.
    static func animationsWithoutValue(in source: String) -> [String] {
        let text = code(source)
        var found: [String] = []
        var from = text.startIndex
        while let range = text.range(of: ".animation(", range: from..<text.endIndex) {
            from = range.upperBound
            let open = text.index(before: range.upperBound)
            let args = group(in: text, opening: open)
            if args.contains("value:") { continue }
            // Not the view modifier: `.animation(minimumInterval:)` of a timeline schedule, or a helper with a labelled
            // first argument.
            if args.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\w+:"#, options: .regularExpression) != nil { continue }
            // The scoped form `.animation(x) { ... }` animates only what is inside its closure.
            let afterStart = text.index(open, offsetBy: args.count + 2, limitedBy: text.endIndex) ?? text.endIndex
            let afterGroup = text[afterStart...]
            if afterGroup.drop(while: { $0 == " " }).first == "{" { continue }
            if isInsideTransition(text, before: range.lowerBound) { continue }
            let line = text[..<range.lowerBound].filter { $0 == "\n" }.count + 1
            found.append("line \(line): \(group(in: text, opening: open))")
        }
        return found
    }

    private static func isInsideTransition(_ text: String, before index: String.Index) -> Bool {
        var depth = 0
        var cursor = index
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            switch text[cursor] {
            case ")": depth += 1
            case "(":
                if depth == 0 {
                    let head = text[..<cursor]
                    if head.hasSuffix(".transition") || head.hasSuffix("AnyTransition") { return true }
                } else { depth -= 1 }
            default: break
            }
        }
        // A transition built in a function or property that returns `AnyTransition`, within the few lines above.
        let lines = text[..<index].split(separator: "\n", omittingEmptySubsequences: false).suffix(5)
        return lines.contains { $0.contains("AnyTransition") }
    }

    /// A spring written with numbers instead of a `MotionTokens` entry.
    static func springLiterals(in source: String) -> [String] {
        let text = code(source)
        let regex = try! NSRegularExpression(pattern: #"spring\(\s*response:\s*[0-9.]+"#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    // MARK: Allowlist

    /// Fast clocks that stay: the file, what the hit must contain (empty means any hit in the file) and the reason.
    /// Everything else under 0.1 s must be a display link (`DisplaySynchronizedView`).
    static let fastClockAllowlist: [(file: String, hit: String, reason: String)] = [
        ("NotchLights.swift", "", "the halo's own frame interval, driven by its light model and capped by the idle CPU test"),
        ("HomeBackdrops.swift", "", "24 fps backdrop clips, the film's own rate"),
        ("HomeWidgetViews.swift", "", "24 fps widget loops, the film's own rate"),
        ("ScribeIdleView.swift", "", "15 fps meeting idle pose, its own sprite rate"),
        ("ScribeMemoryMascot.swift", "", "12 fps sprite, the clip's own rate"),
        ("OnboardingMascot.swift", "", "24 fps sprite, the clip's own rate"),
        ("WavesPage.swift", "", "60 fps audio meter, a divisor of 120"),
        ("OnboardingVisuals.swift", "", "24 fps film-rate stage in the welcome guide"),
        ("MascotMotion.swift", "", "the mascot's frame clock; its rate comes from the clip (MotionRules.fps)"),
        ("TopBarViews.swift", "TimelineView(", "the Scribe meeting ticker at 20 fps; meeting card motion is left alone"),
    ]

    static func isAllowed(file: String, hit: String) -> Bool {
        fastClockAllowlist.contains { $0.file == file && ($0.hit.isEmpty || hit.contains($0.hit)) }
    }

    // MARK: Tests on fixtures

    @Test func aFastTickingViewIsFlagged() {
        #expect(!Self.fastClocks(in: "TickingView(interval: 1 / 30, paused: x) { c in }").isEmpty)
        #expect(!Self.fastClocks(in: "TickingView(interval: Motion.reduced ? 1 : 1.0 / 30) { c in }").isEmpty)
        #expect(!Self.fastClocks(in: "TimelineView(.animation(minimumInterval: 1 / 24)) { c in }").isEmpty)
        #expect(!Self.fastClocks(in: "TimelineView(.periodic(from: Date(), by: 1.0 / 20)) { c in }").isEmpty)
        #expect(Self.fastClocks(in: "TickingView(interval: 1) { c in }").isEmpty)
        #expect(Self.fastClocks(in: "TickingView(interval: 0.5) { c in }").isEmpty)
        #expect(Self.fastClocks(in: "// TickingView(interval: 1 / 30)").isEmpty)
    }

    @Test func anAnimationWithoutAValueIsFlaggedOutsideATransition() {
        #expect(!Self.animationsWithoutValue(in: "Text(\"a\").animation(.easeIn)").isEmpty)
        #expect(Self.animationsWithoutValue(in: "Text(\"a\").animation(.easeIn, value: x)").isEmpty)
        #expect(Self.animationsWithoutValue(in: ".transition(.opacity.animation(.easeIn))").isEmpty)
        #expect(Self.animationsWithoutValue(in: "view.animation(entrance.animation) {\n $0.opacity(1)\n }").isEmpty)
        #expect(Self.animationsWithoutValue(in: "TimelineView(.animation(minimumInterval: 1 / 24)) { c in }").isEmpty)
        #expect(Self.animationsWithoutValue(in: "func removal() -> AnyTransition {\n .opacity\n .animation(.easeIn)\n }").isEmpty)
        #expect(Self.animationsWithoutValue(in: ".transition(.asymmetric(\n insertion: .opacity.animation(.easeIn),\n removal: .scale.animation(.easeOut)))").isEmpty)
    }

    @Test func aSpringWrittenWithNumbersIsFlagged() {
        #expect(!Self.springLiterals(in: ".animation(.spring(response: 0.34, dampingFraction: 0.82), value: x)").isEmpty)
        #expect(Self.springLiterals(in: ".spring(response: token.response, dampingFraction: token.damping)").isEmpty)
        #expect(Self.springLiterals(in: "// spring(response: 0.3, dampingFraction: 0.7)").isEmpty)
    }

    // MARK: Tests on the real tree

    private static func swiftFiles(under folder: String? = nil) -> [URL] {
        let root = folder.map { sources.appendingPathComponent($0) } ?? sources
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
    }

    @Test func noVisibleMotionRunsOnAFastRunLoopClockOutsideTheAllowlist() throws {
        var problems: [String] = []
        for file in Self.swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for hit in Self.fastClocks(in: source) where !Self.isAllowed(file: file.lastPathComponent, hit: hit) {
                problems.append("\(file.lastPathComponent): \(hit)")
            }
        }
        #expect(problems.isEmpty, "use DisplaySynchronizedView at Motion.ambientFPS, or allowlist with a reason: \(problems)")
        for entry in Self.fastClockAllowlist { #expect(!entry.reason.isEmpty, "\(entry.file) needs a reason") }
    }

    @Test func everyAllowlistedFileStillExists() throws {
        let names = Set(Self.swiftFiles().map(\.lastPathComponent))
        for entry in Self.fastClockAllowlist { #expect(names.contains(entry.file), "\(entry.file) is gone: remove it from the allowlist") }
    }

    @Test func theAmbientLoopsRunOnTheDisplayLink() throws {
        for path in ["Notch/NotchView.swift", "TopBar/TopBarViews.swift", "Overlay/BuddyOverlayView.swift", "Voice/ThinkingOrb.swift",
                     "Avatar/LivingMascot.swift", "TopBar/GlanceHomeCards.swift", "App/OnboardingView.swift", "Notch/GlassBloom.swift"] {
            let source = try String(contentsOf: Self.sources.appendingPathComponent(path), encoding: .utf8)
            #expect(source.contains("DisplaySynchronizedView("), "\(path) should drive its motion from the display link")
        }
        let bloom = try String(contentsOf: Self.sources.appendingPathComponent("Notch/GlassBloom.swift"), encoding: .utf8)
        #expect(bloom.contains("until:"), "the bloom stops its link at an end time")
        let buddy = try String(contentsOf: Self.sources.appendingPathComponent("Overlay/BuddyOverlayView.swift"), encoding: .utf8)
        #expect(buddy.contains("Motion.spinnerFPS"), "the spinner turns at the display rate")
    }

    @Test func noAnimationFiresForEveryChange() throws {
        var problems: [String] = []
        for file in Self.swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for hit in Self.animationsWithoutValue(in: source) { problems.append("\(file.lastPathComponent) \(hit)") }
        }
        #expect(problems.isEmpty, "add value: or move it into a transition: \(problems)")
    }

    @Test func noSpringNumbersLiveInTheNotchOrTopBarViews() throws {
        var problems: [String] = []
        for folder in ["Notch", "TopBar"] {
            for file in Self.swiftFiles(under: folder) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for hit in Self.springLiterals(in: source) { problems.append("\(file.lastPathComponent): \(hit)") }
            }
        }
        #expect(problems.isEmpty, "read the spring from MotionTokens through Motion.spring: \(problems)")
    }
}
