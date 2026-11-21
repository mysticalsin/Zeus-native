import Foundation

/// Settings rows read from the production sidebar source. Notch, picker, motion, scribe,
/// dictation, budget, and now-playing contracts live on ZeusCore types.
struct SettingsSectionRef: Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var group: String
}

enum UIUXSourceMap {
    static let canonicalTwelve = [
        "general", "appearance", "notifications", "sounds", "voice", "dictation",
        "shortcuts", "integrations", "permissions", "privacy", "diagnostics", "license",
    ]


    static func sidebar(in window: String) -> [SettingsSectionRef] {
        let enumBody = slice(window, from: "enum GSSection", until: "var id: String")
        let caseLines = enumBody.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ") }
        var order: [String] = []
        for line in caseLines {
            let rest = line.replacingOccurrences(of: "case ", with: "")
            for raw in rest.split(separator: ",") {
                let name = raw.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { order.append(name) }
            }
        }
        let titles = pairs(in: slice(window, from: "var title: String", until: "var symbol: String"))
        let groups = groupMembers(in: slice(window, from: "var group: Group", until: "static let iPhonePairingAvailable"))
        let phone = !window.contains("static let iPhonePairingAvailable = false")
        let groupOrder = ["settings", "tools", "app"]
        var rows: [SettingsSectionRef] = []
        for group in groupOrder {
            for id in order where groups[id] == group {
                if id == "iPhone" && !phone { continue }
                rows.append(SettingsSectionRef(id: id, title: titles[id] ?? id, group: group))
            }
        }
        return rows
    }


    private static func groupMembers(in body: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in body.components(separatedBy: "\n") where line.contains("case .") && line.contains(":") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let group = parts[1].replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
            let members = parts[0].replacingOccurrences(of: "case", with: "")
            for raw in members.split(separator: ",") {
                let name = raw.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { map[name] = group }
            }
        }
        return map
    }

    private static func pairs(in body: String) -> [String: String] {
        var map: [String: String] = [:]
        let pattern = #"case \.([A-Za-z0-9]+): "([^"]+)""#
        for match in matches(pattern, in: body) where match.count >= 3 {
            map[match[1]] = match[2]
        }
        return map
    }


    private static func slice(_ text: String, from start: String, until end: String) -> String {
        guard let lower = text.range(of: start)?.lowerBound else { return "" }
        let rest = text[lower...]
        guard let upper = rest.range(of: end)?.lowerBound else { return String(rest) }
        return String(rest[..<upper])
    }


    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let span = match.range(at: index)
                guard span.location != NSNotFound, let range = Range(span, in: text) else { return nil }
                return String(text[range])
            }
        }
    }
}

struct UIUXFinding: Codable, Equatable {
    var id: String
    var kind: String
    var surface: String
    var file: String
    var line: Int
    var detail: String
    /// `open`: the site is still an open finding. The case runs and tracks it.
    /// `closed`: the site is gone from the scan.
    var expect: String = "open"

    enum CodingKeys: String, CodingKey {
        case id, kind, surface, file, line, detail, expect
    }

    init(id: String, kind: String, surface: String, file: String, line: Int, detail: String, expect: String = "open") {
        self.id = id
        self.kind = kind
        self.surface = surface
        self.file = file
        self.line = line
        self.detail = detail
        self.expect = expect
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(String.self, forKey: .kind)
        surface = try values.decode(String.self, forKey: .surface)
        file = try values.decode(String.self, forKey: .file)
        line = try values.decode(Int.self, forKey: .line)
        detail = try values.decode(String.self, forKey: .detail)
        expect = try values.decodeIfPresent(String.self, forKey: .expect) ?? "open"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(surface, forKey: .surface)
        try values.encode(file, forKey: .file)
        try values.encode(line, forKey: .line)
        try values.encode(detail, forKey: .detail)
        try values.encode(expect, forKey: .expect)
    }
}

struct UIUXFindingCatalog: Codable, Equatable {
    var schema: Int
    var findings: [UIUXFinding]
}

enum UIUXAudit {
    static let surfaceRoots = [
        "Sources/Zeus/Notch",
        "Sources/Zeus/TopBar",
        "Sources/Zeus/Settings",
        "Sources/Zeus/Scribe",
        "Sources/Zeus/Agents",
        "Sources/Zeus/Dictation",
    ]

    static let controlKinds = [
        "NotchActionButton", "NotchButton", "SecureField", "TextField", "DisclosureGroup",
        "Button", "Toggle", "Slider", "Picker", "Stepper", "Link",
    ]

    static let reduceMotionMarkers = [
        "reduceMotion", "Motion.reduced", "Motion.live", "Motion.reducible", "Motion.spring",
        "Motion.page", "Motion.feedback", "TopBarStyle.openSpring", "TopBarStyle.closeMotion",
        "TopBarStyle.pageSpring", "TopBarStyle.openHeightSpring", "wingsSpring", "AlertStyle.crossfade",
        "ScribeMeetingCardMotion.crossfade", "reducedFade", "reducedMotionFade", "breath.halfCycle",
    ]

    static func scan(root: URL) -> [UIUXFinding] {
        let files = swiftFiles(root: root)
        var drafts: [(kind: String, surface: String, file: String, line: Int, detail: String)] = []
        var typeSeen = Set<String>()
        for file in files {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let folder = surfaceRoots.first { relative.hasPrefix($0) } ?? "surface"
            let surface = folder.split(separator: "/").last.map(String.init) ?? folder
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let code = stripComments(source)
            for site in controls(in: code) where !site.complete {
                drafts.append(("accessibility", surface, relative, site.line, site.detail))
            }
            for site in motionSites(in: code) {
                if site.literal {
                    drafts.append(("motion-literal", surface, relative, site.line, site.detail))
                }
                if site.missingReduce {
                    drafts.append(("motion-reduce", surface, relative, site.line, site.detail))
                }
            }
            if code.contains("ultraThinMaterial") || code.contains("thinMaterial") || code.contains("regularMaterial")
                || code.contains(".ultraThin") || code.contains("Material.") {
                if !code.contains("reduceTransparency") && !code.contains("accessibilityReduceTransparency") {
                    drafts.append(("reduce-transparency", surface, relative, 1, "Material without a Reduce Transparency branch"))
                }
            }
            if (code.contains(".system(size:") || code.contains("Font.system(size")) && !typeSeen.contains(surface) {
                typeSeen.insert(surface)
            }
        }
        for folderPath in surfaceRoots {
            let name = folderPath.split(separator: "/").last.map(String.init) ?? folderPath
            guard typeSeen.contains(name) else { continue }
            let folder = root.appendingPathComponent(folderPath)
            let tree = (try? folderResource(folder)) ?? ""
            if !tree.contains("dynamicTypeSize") && !tree.contains("DynamicTypeSize") {
                drafts.append(("dynamic-type", name, folderPath, 1, "Fixed type sizes and no dynamic type ramp"))
            }
        }
        let joined = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        if !joined.contains("accessibilityIdentifier(\"decision") && !joined.contains("accessibilityIdentifier(\"hub.decision") {
            drafts.append(("decision-row", "decision", "Sources/ZeusCore/Decision/DecisionProvider.swift", 1,
                           "Decision results have no accessibility identifier on a row"))
        }
        if let notch = files.first(where: { $0.lastPathComponent == "NotchView.swift" }),
           let text = try? String(contentsOf: notch, encoding: .utf8),
           text.contains("NotchButton(title: \"Approve\"") && !text.contains("keyboardShortcut(.cancelAction)") {
            drafts.append(("escape-key", "approval", "Sources/Zeus/Notch/NotchView.swift", 1,
                           "Escape is not bound on the approval card or the expanded panel"))
        }
        return number(drafts)
    }

    /// File plus the snippet in `detail`. The line is not part of the match, so a moved site stays open.
    static func sameSite(_ lhs: UIUXFinding, _ rhs: UIUXFinding) -> Bool {
        lhs.file == rhs.file && lhs.kind == rhs.kind && lhs.detail == rhs.detail
    }

    static func number(_ drafts: [(kind: String, surface: String, file: String, line: Int, detail: String)]) -> [UIUXFinding] {
        let sorted = drafts.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            if lhs.file != rhs.file { return lhs.file < rhs.file }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.detail < rhs.detail
        }
        var counts: [String: Int] = [:]
        return sorted.map { draft in
            let next = (counts[draft.kind] ?? 0) + 1
            counts[draft.kind] = next
            let prefix: String
            switch draft.kind {
            case "accessibility": prefix = "A11Y"
            case "motion-literal": prefix = "MOTION"
            case "motion-reduce": prefix = "REDUCE"
            case "reduce-transparency": prefix = "GLASS"
            case "dynamic-type": prefix = "TYPE"
            case "decision-row": prefix = "DECISION"
            case "escape-key": prefix = "ESCAPE"
            default: prefix = "GAP"
            }
            return UIUXFinding(
                id: String(format: "ZB-UIUX-%@-%03d", prefix, next),
                kind: draft.kind,
                surface: draft.surface,
                file: draft.file,
                line: draft.line,
                detail: draft.detail
            )
        }
    }

    struct ControlSite: Equatable {
        var line: Int
        var complete: Bool
        var detail: String
    }

    struct MotionSite: Equatable {
        var line: Int
        var literal: Bool
        var missingReduce: Bool
        var detail: String
    }

    static func controls(in source: String) -> [ControlSite] {
        let pattern = #"\b(\#(controlKinds.joined(separator: "|")))\s*[\(\{]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        var sites: [ControlSite] = []
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: source), let kindRange = Range(match.range(at: 1), in: source) else { continue }
            if insideRepresentation(source, at: range.lowerBound) { continue }
            let kind = String(source[kindRange])
            let window = statement(in: source, from: range.lowerBound)
            let label = hasLabel(window, kind: kind)
            let trait = controlKinds.contains(kind) || window.contains("accessibilityAddTraits") || window.contains("accessibilityRepresentation")
            let identifier = window.contains("accessibilityIdentifier(")
            let line = lineNumber(source, at: range.lowerBound)
            let missing = [label ? nil : "label", trait ? nil : "trait", identifier ? nil : "identifier"].compactMap { $0 }
            sites.append(ControlSite(
                line: line,
                complete: missing.isEmpty,
                detail: "\(kind) missing \(missing.joined(separator: ", "))"
            ))
        }
        return sites
    }

    static func motionSites(in source: String) -> [MotionSite] {
        let pattern = #"\.(?:animation|easeInOut|easeOut|easeIn|linear|spring)\(|\bwithAnimation\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        var sites: [MotionSite] = []
        var covered: [Range<String.Index>] = []
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: source) else { continue }
            if covered.contains(where: { $0.contains(range.lowerBound) }) { continue }
            let token = String(source[range])
            let isOuter = token.hasPrefix(".animation") || token.hasPrefix("withAnimation")
            let body = callBody(in: source, open: source.index(before: range.upperBound))
            let span = source.index(range.lowerBound, offsetBy: -min(400, source.distance(from: source.startIndex, to: range.lowerBound)), limitedBy: source.startIndex) ?? source.startIndex
            let around = String(source[span..<range.upperBound]) + body
            if !isOuter && around.contains(".animation(") { continue }
            let literals = literalArguments(in: body)
            let instant = body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("nil")
            let reduced = instant || reduceMotionMarkers.contains { around.contains($0) }
            if literals.isEmpty && reduced { continue }
            if !literals.isEmpty || !reduced {
                let end = source.index(range.lowerBound, offsetBy: body.count + 1, limitedBy: source.endIndex) ?? source.endIndex
                covered.append(range.lowerBound..<end)
                sites.append(MotionSite(
                    line: lineNumber(source, at: range.lowerBound),
                    literal: !literals.isEmpty,
                    missingReduce: !reduced,
                    detail: literals.isEmpty ? "animation without a Reduce Motion branch" : literals.joined(separator: ", ")
                ))
            }
        }
        return sites
    }

    static func fixtureControls(_ source: String) -> [ControlSite] { controls(in: stripComments(source)) }
    static func fixtureMotion(_ source: String) -> [MotionSite] { motionSites(in: stripComments(source)) }

    static func stripComments(_ source: String) -> String {
        var out = ""
        var inString = false
        var inLine = false
        var inBlock = false
        let chars = Array(source)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : "\0"
            if inLine {
                if char == "\n" { inLine = false; out.append(char) } else { out.append(" ") }
            } else if inBlock {
                if char == "*" && next == "/" {
                    inBlock = false
                    out.append("  ")
                    index += 1
                } else {
                    out.append(char == "\n" ? "\n" : " ")
                }
            } else if inString {
                out.append(char)
                if char == "\\" && index + 1 < chars.count {
                    out.append(next)
                    index += 1
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "/" && next == "/" {
                inLine = true
                out.append("  ")
                index += 1
            } else if char == "/" && next == "*" {
                inBlock = true
                out.append("  ")
                index += 1
            } else {
                if char == "\"" { inString = true }
                out.append(char)
            }
            index += 1
        }
        return out
    }

    private static func hasLabel(_ window: String, kind: String) -> Bool {
        if window.contains("accessibilityLabel(") || window.contains("accessibilityRepresentation") { return true }
        if window.contains("title:") || window.contains("Text(") || window.contains("configuration.label") { return true }
        if window.contains("section.title") || window.contains("tab.help") || window.contains("tab.title") { return true }
        let titled = ["Button(\"", "Toggle(\"", "TextField(\"", "SecureField(\"", "Link(\"", "Slider(", "Picker("]
        return titled.contains { window.contains($0) }
    }

    private static func insideRepresentation(_ source: String, at index: String.Index) -> Bool {
        let back = source.index(index, offsetBy: -min(500, source.distance(from: source.startIndex, to: index)), limitedBy: source.startIndex) ?? source.startIndex
        guard let marker = source[back..<index].range(of: "accessibilityRepresentation", options: .backwards) else { return false }
        var depth = 0
        var cursor = marker.upperBound
        while cursor < index {
            let char = source[cursor]
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            cursor = source.index(after: cursor)
        }
        return depth > 0
    }

    /// A call keeps going through a trailing closure, a `label:` argument, or a modifier chain.
    private static func continuesCall(_ text: String, at cursor: String.Index) -> Bool {
        var look = cursor
        while look < text.endIndex, text[look].isWhitespace { look = text.index(after: look) }
        guard look < text.endIndex else { return false }
        let char = text[look]
        if char == "{" || char == "." || char == ":" || char == "(" { return true }
        guard char.isLetter else { return false }
        var token = look
        while token > text.startIndex {
            let before = text.index(before: token)
            if text[before].isLetter || text[before] == "_" { token = before } else { break }
        }
        if token > text.startIndex, text[text.index(before: token)] == "." { return true }
        var name = look
        while name < text.endIndex, text[name].isLetter || text[name] == "_" { name = text.index(after: name) }
        while name < text.endIndex, text[name].isWhitespace { name = text.index(after: name) }
        return name < text.endIndex && text[name] == ":"
    }

    private static func statement(in text: String, from start: String.Index) -> String {
        var cursor = start
        var paren = 0
        var brace = 0
        var opened = false
        while cursor < text.endIndex {
            let char = text[cursor]
            if char == "\"" {
                cursor = skipString(text, cursor)
                continue
            }
            if char == "(" { paren += 1; opened = true }
            else if char == ")" { paren = max(0, paren - 1) }
            else if char == "{" { brace += 1; opened = true }
            else if char == "}" { brace = max(0, brace - 1) }
            cursor = text.index(after: cursor)
            if opened && paren == 0 && brace == 0 && !continuesCall(text, at: cursor) { break }
        }
        var end = cursor
        while end < text.endIndex {
            var look = end
            while look < text.endIndex, text[look].isWhitespace { look = text.index(after: look) }
            guard look < text.endIndex, text[look] == "." else { break }
            end = endOfCall(text, from: look)
        }
        return String(text[start..<end])
    }

    private static func endOfCall(_ text: String, from start: String.Index) -> String.Index {
        var cursor = start
        var paren = 0
        var brace = 0
        var opened = false
        while cursor < text.endIndex {
            let char = text[cursor]
            if char == "\"" {
                cursor = skipString(text, cursor)
                continue
            }
            if char == "(" { paren += 1; opened = true }
            else if char == ")" { paren = max(0, paren - 1) }
            else if char == "{" { brace += 1; opened = true }
            else if char == "}" { brace = max(0, brace - 1) }
            else if char == "\n" && opened && paren == 0 && brace == 0 {
                return cursor
            }
            cursor = text.index(after: cursor)
            if opened && paren == 0 && brace == 0 && !continuesCall(text, at: cursor) { return cursor }
        }
        return cursor
    }

    private static func callBody(in text: String, open: String.Index) -> String {
        var depth = 0
        var cursor = open
        let start = text.index(after: open)
        while cursor < text.endIndex {
            let char = text[cursor]
            if char == "\"" {
                cursor = skipString(text, cursor)
                continue
            }
            if char == "(" { depth += 1 }
            if char == ")" {
                depth -= 1
                if depth == 0 { return String(text[start..<cursor]) }
            }
            cursor = text.index(after: cursor)
        }
        return String(text[start...])
    }

    private static func literalArguments(in body: String) -> [String] {
        let pattern = #"(?:duration|response|dampingFraction|delay)\s*:\s*(?!MotionTokens)([0-9]+(?:\.[0-9]+)?)|\.delay\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)"#
        return UIUXSourceMap.matches(pattern, in: body).compactMap { row in
            row.dropFirst().first { !$0.isEmpty && $0.first?.isNumber == true }
        }
    }

    private static func skipString(_ text: String, _ open: String.Index) -> String.Index {
        var cursor = text.index(after: open)
        while cursor < text.endIndex {
            if text[cursor] == "\\" {
                cursor = text.index(after: cursor)
                if cursor < text.endIndex { cursor = text.index(after: cursor) }
                continue
            }
            if text[cursor] == "\"" { return text.index(after: cursor) }
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private static func lineNumber(_ text: String, at index: String.Index) -> Int {
        text[..<index].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private static func swiftFiles(root: URL) -> [URL] {
        surfaceRoots.flatMap { relative -> [URL] in
            let folder = root.appendingPathComponent(relative)
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        }
    }

    private static func folderResource(_ folder: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return "" }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}

enum UIUXRepo {
    static func root(file: String = #filePath) -> URL? {
        if let override = ProcessInfo.processInfo.environment["ZEUS_UIUX_ROOT"] {
            let pointed = URL(fileURLWithPath: override)
            let token = pointed.appendingPathComponent("Sources/ZeusCore/TopBar/MotionTokens.swift")
            if FileManager.default.fileExists(atPath: token.path) { return pointed }
        }
        var url = URL(fileURLWithPath: file)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let token = url.appendingPathComponent("Sources/ZeusCore/TopBar/MotionTokens.swift")
            let package = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: token.path),
               let text = try? String(contentsOf: package, encoding: .utf8),
               text.contains("name: \"Zeus\"") {
                return url
            }
        }
        return nil
    }
}
