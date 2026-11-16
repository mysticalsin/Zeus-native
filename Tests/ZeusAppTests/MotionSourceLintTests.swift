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

    /// Source with comments blanked (`//` and `/* */`, newlines kept), so rules do not read prose. A `//` inside a
    /// string literal (a URL, say) is not a comment.
    static func code(_ source: String) -> String {
        var out = ""
        var inString = false, inLine = false, inBlock = false
        let chars = Array(source)
        var index = 0
        while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : "\0"
            if inLine {
                if c == "\n" { inLine = false; out.append(c) } else { out.append(" ") }
            } else if inBlock {
                if c == "*" && next == "/" { inBlock = false; out.append("  "); index += 1 } else { out.append(c == "\n" ? "\n" : " ") }
            } else if inString {
                out.append(c)
                if c == "\\" && index + 1 < chars.count { out.append(next); index += 1 } else if c == "\"" { inString = false }
            } else if c == "/" && next == "/" {
                inLine = true; out.append("  "); index += 1
            } else if c == "/" && next == "*" {
                inBlock = true; out.append("  "); index += 1
            } else {
                if c == "\"" { inString = true }
                out.append(c)
            }
            index += 1
        }
        return out
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

    /// The interval expression of a clock call: what follows `label` up to the next top-level comma or the end.
    static func intervalExpressions(in source: String) -> [(call: String, expression: String?)] {
        let text = code(source)
        var found: [(String, String?)] = []
        var from = text.startIndex
        while let range = text.range(of: #"(TickingView|TimelineView)\("#, options: .regularExpression, range: from..<text.endIndex) {
            from = range.upperBound
            let open = text.index(before: range.upperBound)
            let args = group(in: text, opening: open)
            let isTicking = text[range].hasPrefix("TickingView")
            let label: String?
            if isTicking { label = "interval:" }
            else if args.contains(".periodic(") { label = "by:" }
            else if args.contains(".animation") { label = "minimumInterval:" }
            else { continue } // another schedule (every minute, explicit): not a frame clock
            guard let labelRange = args.range(of: label!) else {
                found.append((isTicking ? "TickingView" : "TimelineView", nil)); continue
            }
            var expression = ""
            var depth = 0
            for ch in args[labelRange.upperBound...] {
                if ch == "(" { depth += 1 }
                if ch == ")" { if depth == 0 { break }; depth -= 1 }
                if ch == "," && depth == 0 { break }
                expression.append(ch)
            }
            found.append((isTicking ? "TickingView" : "TimelineView", expression.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return found
    }

    /// A plain number or quotient: `0.5`, `1 / 30`, `1.0 / 24.0`.
    static func literal(_ expression: String) -> Double? {
        let parts = expression.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let values = parts.compactMap { Double($0) }
        guard values.count == parts.count, (1...2).contains(values.count) else { return nil }
        return values.count == 2 ? (values[1] == 0 ? nil : values[0] / values[1]) : values[0]
    }

    /// A ternary's branches (the condition is not an interval), or the whole expression.
    static func branches(of expression: String) -> [String] {
        guard let question = expression.firstIndex(of: "?") else { return [expression] }
        let rest = expression[expression.index(after: question)...]
        guard let colon = rest.firstIndex(of: ":") else { return [String(rest)] }
        return [String(rest[..<colon]), String(rest[rest.index(after: colon)...])].map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Named intervals that may stand in for a literal, with the reason. A match is by prefix.
    static let namedIntervals: [(name: String, reason: String)] = [
        ("NotchLights.frameInterval", "the halo lights' frame interval: the mascot's top clip rate (24 fps), a CPU-capped grid"),
        ("reducedInterval", "the edge wave's fixed 0.1 s step for Reduce Motion"),
        ("clock.interval", "the mascot's clip rate (12, 20 or 24 fps), set by `MascotClipClock`"),
        ("Self.clipInterval(", "the mascot's clip rate for a pinned pose preview"),
    ]

    /// Visible motion must not run on a run-loop clock faster than 0.1 s: `TickingView(interval:)`, and
    /// `TimelineView(.animation(minimumInterval:))` or `.periodic(by:)`.
    static func fastClocks(in source: String) -> [String] {
        intervalExpressions(in: source).compactMap { call, expression in
            guard let expression, branches(of: expression).contains(where: { (literal($0) ?? 1) < 0.1 }) else { return nil }
            return "\(call)(interval:\(expression))"
        }
    }

    /// Intervals that are not a literal of 0.1 s or more and not a named constant on `namedIntervals`, or missing:
    /// a clock whose rate cannot be read from the source is not allowed.
    static func unreadableClocks(in source: String) -> [String] {
        var found: [String] = []
        for (call, expression) in intervalExpressions(in: source) {
            guard let expression else { found.append("\(call) with no interval"); continue }
            for branch in branches(of: expression) where literal(branch) == nil {
                if namedIntervals.contains(where: { branch.hasPrefix($0.name) }) { continue }
                found.append("\(call)(interval:\(branch))")
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

    /// Only when the call belongs to a transition expression: inside `.transition(...)`, or in the same statement
    /// as `AnyTransition`, `.asymmetric(` or `.combined(with:`. A statement runs back over lines that continue it
    /// (they start with `.` or `)`), to the line that opens it.
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
                    if head.hasSuffix(".transition") { return true }
                } else { depth -= 1 }
            default: break
            }
        }
        var lines = text[..<index].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var statement: [String] = []
        while let line = lines.popLast() {
            statement.append(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !(trimmed.hasPrefix(".") || trimmed.hasPrefix(")") || trimmed.isEmpty) { break }
        }
        let joined = statement.joined(separator: "\n")
        return ["AnyTransition", ".asymmetric(", ".combined(with:"].contains { joined.contains($0) }
    }

    /// A spring written with numbers or a stock preset instead of a `MotionTokens` entry.
    static func springLiterals(in source: String) -> [String] {
        let text = code(source)
        let pattern = #"spring\(\s*(?:response|duration|bounce):\s*[0-9.]+|interpolatingSpring\(|\.(?:snappy|bouncy|smooth)\b(?!\s*\()|\.(?:snappy|bouncy|smooth)\("#
        let regex = try! NSRegularExpression(pattern: pattern)
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
        #expect(Self.fastClocks(in: "/* TickingView(interval: 1 / 30) */").isEmpty)
    }

    @Test func anAnimationWithoutAValueIsFlaggedOutsideATransition() {
        #expect(!Self.animationsWithoutValue(in: "Text(\"a\").animation(.easeIn)").isEmpty)
        #expect(Self.animationsWithoutValue(in: "Text(\"a\").animation(.easeIn, value: x)").isEmpty)
        #expect(Self.animationsWithoutValue(in: ".transition(.opacity.animation(.easeIn))").isEmpty)
        #expect(Self.animationsWithoutValue(in: "view.animation(entrance.animation) {\n $0.opacity(1)\n }").isEmpty)
        #expect(Self.animationsWithoutValue(in: "TimelineView(.animation(minimumInterval: 1 / 24)) { c in }").isEmpty)
        #expect(Self.animationsWithoutValue(in: "func removal() -> AnyTransition {\n .opacity\n .animation(.easeIn)\n }").isEmpty)
        #expect(Self.animationsWithoutValue(in: "return .scale(scale: 0.9).combined(with: .opacity)\n .animation(.easeIn)").isEmpty)
        #expect(Self.animationsWithoutValue(in: ".transition(.asymmetric(\n insertion: .opacity.animation(.easeIn),\n removal: .scale.animation(.easeOut)))").isEmpty)
        // A transition elsewhere in the file does not excuse an unkeyed animation in a different statement.
        #expect(!Self.animationsWithoutValue(in: "func removal() -> AnyTransition {\n .opacity\n }\n let x = Text(\"a\")\n .animation(.easeIn)").isEmpty)
        #expect(!Self.animationsWithoutValue(in: ".transition(.opacity)\n Text(\"b\")\n .animation(.easeIn)").isEmpty)
    }

    @Test func aSpringWrittenWithNumbersOrAPresetIsFlagged() {
        #expect(!Self.springLiterals(in: ".animation(.spring(response: 0.34, dampingFraction: 0.82), value: x)").isEmpty)
        #expect(!Self.springLiterals(in: ".animation(.spring(duration: 0.4, bounce: 0.1), value: x)").isEmpty)
        #expect(!Self.springLiterals(in: ".animation(.interpolatingSpring(stiffness: 100, damping: 10), value: x)").isEmpty)
        #expect(!Self.springLiterals(in: ".animation(.snappy, value: x)").isEmpty)
        #expect(!Self.springLiterals(in: ".animation(.bouncy(duration: 0.3), value: x)").isEmpty)
        #expect(!Self.springLiterals(in: ".animation(.smooth, value: x)").isEmpty)
        #expect(Self.springLiterals(in: ".spring(response: token.response, dampingFraction: token.damping)").isEmpty)
        #expect(Self.springLiterals(in: "// spring(response: 0.3, dampingFraction: 0.7)").isEmpty)
        #expect(Self.springLiterals(in: "/* .animation(.snappy) */ let x = 1").isEmpty)
        #expect(Self.springLiterals(in: "/* start\n .spring(response: 0.3) \n end */").isEmpty)
    }

    @Test func commentsAreBlankedButStringsKeepTheirSlashes() {
        #expect(!Self.code("let url = \"https://example.com\" // note").contains("note"))
        #expect(Self.code("let url = \"https://example.com\" // note").contains("https://example.com"))
        // A comment-looking string must not hide the code after it.
        #expect(Self.fastClocks(in: "let s = \"//\"; TickingView(interval: 1 / 30) { c in }").count == 1)
        #expect(Self.code("a /* x\ny */ b").filter { $0 == "\n" }.count == 1)
    }

    @Test func aClockWhoseRateCannotBeReadIsFlagged() {
        #expect(!Self.unreadableClocks(in: "TickingView(interval: someRate) { c in }").isEmpty)
        #expect(!Self.unreadableClocks(in: "TickingView(interval: Motion.reduced ? 1 : rate) { c in }").isEmpty)
        #expect(!Self.unreadableClocks(in: "TimelineView(.animation) { c in }").isEmpty)
        #expect(!Self.unreadableClocks(in: "TimelineView(.periodic(from: .now, by: step)) { c in }").isEmpty)
        #expect(Self.unreadableClocks(in: "TickingView(interval: 1) { c in }").isEmpty)
        #expect(Self.unreadableClocks(in: "TickingView(interval: Motion.reduced ? 0.5 : NotchLights.frameInterval) { c in }").isEmpty)
        #expect(Self.unreadableClocks(in: "TimelineView(.periodic(from: .now, by: 0.25)) { c in }").isEmpty)
        #expect(Self.unreadableClocks(in: "TimelineView(.everyMinute) { c in }").isEmpty)
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

    @Test func everyClockRateCanBeReadFromTheSource() throws {
        var problems: [String] = []
        for file in Self.swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for hit in Self.unreadableClocks(in: source) { problems.append("\(file.lastPathComponent): \(hit)") }
        }
        #expect(problems.isEmpty, "use a literal of 0.1 s or more, or add the named constant to namedIntervals with a reason: \(problems)")
        for entry in Self.namedIntervals { #expect(!entry.reason.isEmpty, "\(entry.name) needs a reason") }
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
