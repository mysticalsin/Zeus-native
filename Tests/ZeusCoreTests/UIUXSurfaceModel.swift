import Foundation

/// Pure UI/UX contracts for the notch, the island, the expanded panel, settings, approvals,
/// decisions, Scribe, Murmure and the hubs. Views are not built here. Reduce Motion and Reduce
/// Transparency are arguments on the spec, never a write to the system setting.
enum ChromePhase: String, Equatable, CaseIterable {
    case idle, hover, peek, expanded
}

enum OpenTrigger: String, Equatable, CaseIterable {
    case hover, click
}

enum ApprovalVerdict: String, Equatable {
    case allow, deny
}

struct ApprovalCard: Equatable {
    var agent: String
    var command: String
    var highRisk: Bool
    var detailsHidden: Bool
    /// A plan or question whose own actions replace the Approve button. Deny stays.
    var ownActions: Bool
    var offersTrust: Bool
    var changePreview: Bool
}

enum ReturnEffect: Equatable {
    case ignored
    case openedTerminal
    case closedPicker
}

struct ChromeDesk: Equatable {
    var phase: ChromePhase = .idle
    var trigger: OpenTrigger = .hover
    var hoverFrom: ChromePhase = .idle
    var voiceOver = false
    var pinned = false
    var calibrating = false
    var menuOpen = false
    var prompterActive = false
    var picker = false
    var sessionCount = 0
    var approval: ApprovalCard?
    var tab = "home"
    var tabStrip = false
    var shiftPeek = false
    var focus = 0
    var verdict: ApprovalVerdict?
    var escapeIgnored = 0
    var bareSwipes = 0

    /// Hover opens only after a dwell, and only while the trigger is hover. A peek is not the panel:
    /// the pointer entering it can still promote it.
    mutating func pointerEntered() {
        guard !calibrating, trigger == .hover, (phase == .idle || phase == .peek) else { return }
        hoverFrom = phase
        phase = .hover
    }

    mutating func dwellFinished() {
        guard phase == .hover, trigger == .hover, !calibrating else { return }
        phase = .expanded
        shiftPeek = false
    }

    mutating func pointerExited() {
        switch phase {
        case .hover:
            phase = hoverFrom
        case .expanded:
            guard !voiceOver, !pinned, !menuOpen, !prompterActive, !picker else { return }
            phase = approval == nil ? .idle : .peek
            tabStrip = false
        case .idle, .peek:
            break
        }
    }

    /// One click. Under the click trigger this opens from idle or peek. It never closes the panel.
    mutating func press() {
        guard !calibrating, trigger == .click, phase != .expanded else { return }
        phase = .expanded
        shiftPeek = false
    }

    /// `count` is 1, 2 or 3. Extra clicks after the panel is open do not dismiss it.
    mutating func clicks(_ count: Int) {
        let times = min(max(count, 1), 3)
        for _ in 0..<times { press() }
    }

    /// Holding the island is a long dwell for the hover trigger, and is not a click.
    mutating func holdIsland() {
        guard trigger == .hover, phase == .hover, !calibrating else { return }
        phase = .expanded
        shiftPeek = false
    }

    mutating func shiftHold() {
        guard phase == .idle || phase == .hover else { return }
        if phase == .idle { hoverFrom = .idle }
        phase = .peek
        shiftPeek = true
    }

    mutating func shiftRelease() {
        guard shiftPeek else { return }
        shiftPeek = false
        guard approval == nil, !picker else { return }
        phase = .idle
    }

    mutating func tabHold() { tabStrip = true }
    mutating func tabRelease() { tabStrip = false }

    mutating func swipeRight(files: Bool) {
        if files {
            tab = "shelf"
            phase = .expanded
            shiftPeek = false
        } else {
            bareSwipes += 1
        }
    }

    /// Escape closes the agent picker. It does not approve, deny, or dismiss the panel.
    mutating func escape() {
        if picker {
            picker = false
            phase = approval == nil ? .idle : .peek
            focus = 0
            return
        }
        escapeIgnored += 1
    }

    mutating func returnKey() -> ReturnEffect {
        if picker {
            let open = sessionCount > 0
            picker = false
            phase = approval == nil ? .idle : .peek
            focus = 0
            return open ? .openedTerminal : .closedPicker
        }
        return .ignored
    }

    mutating func openPicker() {
        picker = true
        tab = "agents"
        phase = .expanded
        focus = 0
    }

    mutating func decide(_ verdict: ApprovalVerdict) {
        guard approval != nil, self.verdict == nil else { return }
        self.verdict = verdict
        approval = nil
        if phase == .peek { phase = .idle }
    }

    func focusTargets(tabs: [String]) -> [String] {
        switch phase {
        case .idle, .hover:
            return ["island"]
        case .peek:
            guard let approval else { return ["peek.card"] }
            if approval.detailsHidden && approval.ownActions { return ["approval.deny"] }
            var row = ["approval.deny", "approval.approve"]
            if approval.offersTrust { row.append("approval.trust") }
            return row
        case .expanded:
            return tabs + ["notch.more"]
        }
    }

    mutating func focusNext(tabs: [String]) { moveFocus(1, tabs: tabs) }
    mutating func focusPrevious(tabs: [String]) { moveFocus(-1, tabs: tabs) }

    private mutating func moveFocus(_ delta: Int, tabs: [String]) {
        let count = focusTargets(tabs: tabs).count
        guard count > 0 else { focus = 0; return }
        focus = min(max(focus + delta, 0), count - 1)
    }
}

enum ContentPhase: String, Equatable, CaseIterable {
    case empty, loading, ready, error, recovery
}

struct ContentDesk: Equatable {
    var phase: ContentPhase = .empty
    private(set) var attempts = 0

    mutating func refresh() {
        switch phase {
        case .empty, .ready, .recovery:
            phase = .loading
        case .loading, .error:
            break
        }
    }

    mutating func succeed() {
        guard phase == .loading || phase == .recovery else { return }
        phase = .ready
        attempts = 0
    }

    mutating func fail() {
        guard phase == .loading || phase == .recovery else { return }
        phase = .error
        attempts += 1
    }

    mutating func retry() {
        guard phase == .error else { return }
        phase = .recovery
    }

    mutating func clear() {
        guard phase == .ready else { return }
        phase = .empty
    }
}

struct SettingsSectionRef: Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var group: String
}

struct SettingsDesk: Equatable {
    var sections: [SettingsSectionRef]
    var index = 0
    var phase: [String: ContentPhase]

    init(sections: [SettingsSectionRef]) {
        self.sections = sections
        self.phase = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, ContentPhase.empty) })
    }

    var focused: SettingsSectionRef? {
        sections.indices.contains(index) ? sections[index] : nil
    }

    mutating func step(_ delta: Int) {
        guard !sections.isEmpty else { return }
        index = min(max(index + delta, 0), sections.count - 1)
    }

    mutating func select(_ id: String) {
        guard let found = sections.firstIndex(where: { $0.id == id }) else { return }
        index = found
    }

    mutating func refreshFocused() { updateFocused { $0.refresh() } }
    mutating func succeedFocused() { updateFocused { $0.succeed() } }
    mutating func failFocused() { updateFocused { $0.fail() } }
    mutating func retryFocused() { updateFocused { $0.retry() } }
    mutating func clearFocused() { updateFocused { $0.clear() } }

    private mutating func updateFocused(_ body: (inout ContentDesk) -> Void) {
        guard let id = focused?.id else { return }
        var desk = ContentDesk(phase: phase[id] ?? .empty)
        body(&desk)
        phase[id] = desk.phase
    }
}

enum HubKind: String, Equatable, CaseIterable {
    case nowPlaying = "hub.nowPlaying"
    case agents = "hub.agents"
    case murmur = "hub.murmur"
}

struct HubDesk: Equatable {
    var kind: HubKind
    var content = ContentDesk()
    var command = ""

    var commandsEnabled: Bool { content.phase == .ready }

    mutating func play() {
        guard commandsEnabled else { return }
        command = "play"
    }

    mutating func reply(_ text: String) {
        guard commandsEnabled else { return }
        command = text.isEmpty ? "" : "reply"
        if text.isEmpty { content.phase = .error }
    }
}

enum ScribePhase: String, Equatable, CaseIterable {
    case idle, loading, recording, ending, writing, notes, error, recovery
}

struct ScribeDesk: Equatable {
    var phase: ScribePhase = .idle
    var permission = true
    var finishing = false

    var endNowEnabled: Bool { phase == .recording && !finishing }
    var keepEnabled: Bool { phase == .ending && !finishing }
    var startEnabled: Bool { phase == .idle || phase == .recovery }

    mutating func start() {
        guard startEnabled else { return }
        if permission {
            phase = .recording
        } else {
            phase = .error
        }
    }

    mutating func endNow() {
        guard endNowEnabled else { return }
        phase = .ending
    }

    mutating func keep() {
        guard keepEnabled else { return }
        phase = .recording
    }

    mutating func countdownFinished() {
        guard phase == .ending else { return }
        finishing = true
        phase = .writing
    }

    mutating func notesReady() {
        guard phase == .writing else { return }
        finishing = false
        phase = .notes
    }

    mutating func fail() {
        guard phase == .recording || phase == .writing || phase == .loading else { return }
        finishing = false
        phase = .error
    }

    mutating func retry() {
        guard phase == .error else { return }
        phase = .recovery
    }
}

enum MurmurMode: String, Equatable, CaseIterable {
    case holdToSpeak
    case pressToToggle
}

enum MurmurPhase: String, Equatable {
    case idle, holding, recording, committing, error, recovery
}

struct MurmurDesk: Equatable {
    var mode: MurmurMode
    var phase: MurmurPhase = .idle
    var permission = true

    mutating func press() {
        guard permission else { phase = .error; return }
        switch mode {
        case .holdToSpeak:
            if phase == .idle || phase == .recovery { phase = .holding }
        case .pressToToggle:
            switch phase {
            case .idle, .recovery: phase = .recording
            case .recording: phase = .committing
            case .holding, .committing, .error: break
            }
        }
    }

    mutating func release() {
        guard mode == .holdToSpeak, phase == .holding else { return }
        phase = .committing
    }

    mutating func commitFinished() {
        guard phase == .committing else { return }
        phase = .idle
    }

    mutating func fail() {
        guard phase == .holding || phase == .recording || phase == .committing else { return }
        phase = .error
    }

    mutating func retry() {
        guard phase == .error else { return }
        phase = .recovery
    }

    /// A second and third click are further presses. Hold-to-speak ignores them until release.
    mutating func clicks(_ count: Int) {
        for _ in 0..<min(max(count, 1), 3) { press() }
    }
}

enum DecisionFault: String, Equatable, CaseIterable {
    case noKey, capReached, inFlight, reconciliation, unavailable, http, badResponse

    var personMustAct: Bool {
        switch self {
        case .noKey, .capReached, .reconciliation: true
        case .inFlight, .unavailable, .http, .badResponse: false
        }
    }
}

struct DecisionRow: Equatable {
    var phase: ContentPhase = .empty
    var fault: DecisionFault?
    var confidence: Double?
    var inFlight = false

    mutating func submit() {
        guard !inFlight else { return }
        guard phase == .empty || phase == .ready || phase == .recovery else { return }
        inFlight = true
        fault = nil
        phase = .loading
    }

    mutating func arrive(confidence: Double) {
        guard phase == .loading else { return }
        inFlight = false
        self.confidence = confidence
        fault = nil
        phase = .ready
    }

    mutating func fail(_ fault: DecisionFault) {
        guard phase == .loading || phase == .recovery else { return }
        inFlight = false
        self.fault = fault
        confidence = nil
        phase = .error
    }

    mutating func retry() -> Bool {
        guard phase == .error, let fault, !fault.personMustAct else { return false }
        phase = .recovery
        return true
    }
}

enum MotionValue: Equatable {
    case spring(response: Double, damping: Double)
    case seconds(Double)
    case scale(Double)
    case instant
}

struct MotionSpec: Equatable {
    var name: String
    var full: MotionValue
    var reduced: MotionValue
}

enum MotionContract {
    /// Springs disappear under Reduce Motion. The short crossfade is the one fade that stays.
    static func specs(from tokens: [String: Double]) -> [MotionSpec] {
        let springs = ["panelOpen", "panelOpenHeight", "panelClose", "panelResize", "cueGrow", "peekContent"]
        var rows: [MotionSpec] = springs.map { name in
            MotionSpec(
                name: name,
                full: .spring(response: tokens[name + ".response"] ?? -1, damping: tokens[name + ".damping"] ?? -1),
                reduced: .instant
            )
        }
        let instantDurations = ["pageOutDuration", "pressDuration", "windowFadeInDuration", "windowFadeOutDuration", "peekContentDelay"]
        rows += instantDurations.map { name in
            MotionSpec(name: name, full: .seconds(tokens[name] ?? -1), reduced: .instant)
        }
        rows.append(MotionSpec(name: "pressScale", full: .scale(tokens["pressScale"] ?? -1), reduced: .scale(1)))
        rows.append(MotionSpec(
            name: "crossfadeDuration",
            full: .seconds(tokens["crossfadeDuration"] ?? -1),
            reduced: .seconds(tokens["crossfadeDuration"] ?? -1)
        ))
        return rows
    }
}

enum SurfaceFill: Equatable {
    case blurred, opaque
}

enum TransparencyContract {
    static func fill(reduceTransparency: Bool) -> SurfaceFill {
        reduceTransparency ? .opaque : .blurred
    }
}

enum TypeStep: String, Equatable, CaseIterable {
    case extraSmall, small, medium, large, extraLarge, extraExtraLarge, extraExtraExtraLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    var scale: Double {
        switch self {
        case .extraSmall: 0.82
        case .small: 0.88
        case .medium: 1
        case .large: 1.12
        case .extraLarge: 1.24
        case .extraExtraLarge: 1.35
        case .extraExtraExtraLarge: 1.5
        case .accessibility1: 1.64
        case .accessibility2: 1.76
        case .accessibility3: 1.9
        case .accessibility4: 2.05
        case .accessibility5: 2.2
        }
    }
}

struct ControlContract: Equatable, Identifiable {
    var id: String
    var label: String
    var trait: String
    var surface: String
}

enum ContractControls {
    static let island = ControlContract(id: "island", label: "Zeus", trait: "button", surface: "island")
    static let more = ControlContract(id: "notch.more", label: "More", trait: "button", surface: "panel")
    static let deny = ControlContract(id: "approval.deny", label: "Deny", trait: "button", surface: "approval")
    static let approve = ControlContract(id: "approval.approve", label: "Approve", trait: "button", surface: "approval")
    static let trust = ControlContract(id: "approval.trust", label: "Allow this whole chat", trait: "button", surface: "approval")
    static let scribeStart = ControlContract(id: "scribe.start", label: "Start", trait: "button", surface: "scribe")
    static let scribeEnd = ControlContract(id: "scribe.endNow", label: "End meeting now", trait: "button", surface: "scribe")
    static let scribeKeep = ControlContract(id: "scribe.keep", label: "Keep recording", trait: "button", surface: "scribe")
    static let scribeMemory = ControlContract(id: "scribe.memory.open", label: "Memory", trait: "button", surface: "scribe")
    static let play = ControlContract(id: "hub.nowPlaying.play", label: "Play", trait: "button", surface: "hub")
    static let reply = ControlContract(id: "hub.agents.reply", label: "Reply", trait: "button", surface: "hub")
    static let murmur = ControlContract(id: "hub.murmur.press", label: "Murmure", trait: "button", surface: "hub")

    static func tab(_ id: String, title: String) -> ControlContract {
        ControlContract(id: "notch.tab.\(id)", label: title, trait: "button", surface: "panel")
    }

    static func sidebar(_ id: String, title: String) -> ControlContract {
        ControlContract(id: "settings.sidebar.\(id)", label: title, trait: "button", surface: "settings")
    }

    static func all(sections: [SettingsSectionRef], tabs: [(id: String, title: String)]) -> [ControlContract] {
        var rows = [island, more, deny, approve, trust, scribeStart, scribeEnd, scribeKeep, scribeMemory, play, reply, murmur]
        rows += sections.map { sidebar($0.id, title: $0.title) }
        rows += tabs.map { tab($0.id, title: $0.title) }
        return rows
    }
}

enum UIUXSourceMap {
    static let canonicalTwelve = [
        "general", "appearance", "notifications", "sounds", "voice", "dictation",
        "shortcuts", "integrations", "permissions", "privacy", "diagnostics", "license",
    ]

    static func dwellTable(in controller: String) -> [String: Int] {
        let body = slice(controller, from: "static var openDelayMilliseconds", until: "static var openTrigger")
        var found: [String: Int] = [:]
        if let fast = first(#"case "Fast":\s*(\d+)"#, in: body) { found["Fast"] = Int(fast) }
        if let relaxed = first(#"case "Relaxed":\s*(\d+)"#, in: body) { found["Relaxed"] = Int(relaxed) }
        if let standard = first(#"default:\s*(\d+)"#, in: body) { found["Standard"] = Int(standard) }
        return found
    }

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

    static func defaultTabs(in layout: String) -> [(id: String, title: String)] {
        let seven = names(in: firstLine(layout, containing: "static let glanceSeven"))
        let row = firstLine(layout, containing: "static let defaultRow")
        let head = names(in: row.split(separator: "+").first.map(String.init) ?? "")
        let tail = names(in: row.components(separatedBy: "dropFirst()").dropFirst().joined())
        let ids = head + Array(seven.dropFirst()) + tail
        let titles = pairs(in: slice(layout, from: "public var title: String", until: "public var help: String"))
        return ids.map { ($0, titles[$0] ?? $0) }
    }

    static func springs(in tokens: String) -> [String: Double] {
        var values: [String: Double] = [:]
        let pattern = #"static let ([A-Za-z0-9]+) = SpringToken\(response: ([0-9.]+), damping: ([0-9.]+)\)"#
        for match in matches(pattern, in: tokens) where match.count >= 4 {
            if let response = Double(match[2]), let damping = Double(match[3]) {
                values[match[1] + ".response"] = response
                values[match[1] + ".damping"] = damping
            }
        }
        let durations = #"static let ([A-Za-z0-9]+) = ([0-9.]+)"#
        for match in matches(durations, in: tokens) where match.count >= 3 {
            if let number = Double(match[2]), values[match[1] + ".response"] == nil {
                values[match[1]] = number
            }
        }
        return values
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

    private static func names(in line: String) -> [String] {
        matches(#"\.([A-Za-z0-9]+)"#, in: line).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func firstLine(_ text: String, containing needle: String) -> String {
        text.components(separatedBy: "\n").first { $0.contains(needle) } ?? ""
    }

    private static func slice(_ text: String, from start: String, until end: String) -> String {
        guard let lower = text.range(of: start)?.lowerBound else { return "" }
        let rest = text[lower...]
        guard let upper = rest.range(of: end)?.lowerBound else { return String(rest) }
        return String(rest[..<upper])
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let row = matches(pattern, in: text).first else { return nil }
        return row.count > 1 ? row[1] : row.first
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
