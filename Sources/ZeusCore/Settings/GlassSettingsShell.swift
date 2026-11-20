import Foundation

/// A page that can host a card. These raw values match the existing sidebar pages.
public enum GlassCardPage: String, Equatable, Sendable {
    case general, license, privacy, about
}

/// Where a section appears. A topbar tab joins the Topbar row. A card sits on an existing page.
public enum GlassSectionPlacement: Equatable, Sendable {
    case topbarTab(Int)
    case cardOn(GlassCardPage, Int)

    public var order: Int {
        switch self {
        case .topbarTab(let order), .cardOn(_, let order): return order
        }
    }
}

/// Placeholder slots for settings sections a later change fills. This change adds no setting key.
public struct GlassSectionSlot: Equatable, Sendable {
    public var id: String
    public var title: String
    public var filled: Bool
    public var keys: [String]
    public var order: Int
    public var enabled: Bool
    public var placement: GlassSectionPlacement

    public init(id: String, title: String, filled: Bool, keys: [String], order: Int = 0, enabled: Bool = true, placement: GlassSectionPlacement = .cardOn(.general, 0)) {
        self.id = id
        self.title = title
        self.filled = filled
        self.keys = keys
        self.order = order
        self.enabled = enabled
        self.placement = placement
    }

    public var isShown: Bool { filled && enabled }
}

public protocol GlassSlotProviding: Sendable {
    static var descriptor: GlassSectionSlot { get }
}

public enum GlassSectionManifest {
    /// The twelve section types. A section change edits its own descriptor, not this list.
    public static let providers: [any GlassSlotProviding.Type] = [
        MediaSectionSlot.self,
        GeneralSectionSlot.self,
        PortalSectionSlot.self,
        SensorySectionSlot.self,
        BatterySectionSlot.self,
        FocusSectionSlot.self,
        WeatherSectionSlot.self,
        LockScreenSectionSlot.self,
        FaceIDSectionSlot.self,
        AccessorySectionSlot.self,
        LicenseSectionSlot.self,
        AutoUpdateSectionSlot.self,
    ]

    public static var slots: [GlassSectionSlot] {
        providers.map { $0.descriptor }
    }

    /// Filled, enabled topbar tabs, in tab order. An unfilled or disabled tab is absent.
    public static func topbarTabs(in slots: [GlassSectionSlot]? = nil) -> [GlassSectionSlot] {
        let source = slots ?? self.slots
        return SettingsSectionRegistry.orderedSlots(source.filter { slot in
            if case .topbarTab = slot.placement { return slot.isShown }
            return false
        })
    }

    /// Filled, enabled cards for one existing page, in card order.
    public static func cards(on page: GlassCardPage, in slots: [GlassSectionSlot]? = nil) -> [GlassSectionSlot] {
        let source = slots ?? self.slots
        return SettingsSectionRegistry.orderedSlots(source.filter { slot in
            if case .cardOn(let card, _) = slot.placement { return card == page && slot.isShown }
            return false
        })
    }

    public static var newSettingKeyCount: Int {
        slots.reduce(0) { $0 + $1.keys.count }
    }

    public static func slotProblems(_ slots: [GlassSectionSlot]) -> [String] {
        var problems: [String] = []
        if !SettingsKeyReachability.duplicateIDs(slots.map(\.id)).isEmpty { problems.append("duplicate") }
        for slot in slots {
            if slot.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("blank id") }
            if slot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("blank title") }
            if !slot.filled && !slot.keys.isEmpty { problems.append("keys while empty") }
        }
        return problems
    }
}

/// Accessibility flags are inputs. Resolving a material never writes a system preference.
public struct GlassSettingsAccess: Equatable, Sendable {
    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var increaseContrast: Bool

    public init(reduceMotion: Bool, reduceTransparency: Bool, increaseContrast: Bool) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

public struct GlassSettingsMaterial: Equatable, Sendable {
    public var translucent: Bool
    public var fillOpacity: Double
    public var highlightOpacity: Double
    public var depth: Double
    public var animationDuration: Double
    public var solidFallback: Bool

    public init(translucent: Bool, fillOpacity: Double, highlightOpacity: Double, depth: Double, animationDuration: Double, solidFallback: Bool) {
        self.translucent = translucent
        self.fillOpacity = fillOpacity
        self.highlightOpacity = highlightOpacity
        self.depth = depth
        self.animationDuration = animationDuration
        self.solidFallback = solidFallback
    }
}

public enum GlassSettingsMaterialRules {
    public static func resolve(_ access: GlassSettingsAccess) -> GlassSettingsMaterial {
        let solid = access.reduceTransparency || access.increaseContrast
        if solid {
            return GlassSettingsMaterial(
                translucent: false,
                fillOpacity: 1,
                highlightOpacity: 0,
                depth: 0,
                animationDuration: access.reduceMotion ? 0 : 0.22,
                solidFallback: true
            )
        }
        return GlassSettingsMaterial(
            translucent: true,
            fillOpacity: 0.72,
            highlightOpacity: 0.16,
            depth: 18,
            animationDuration: access.reduceMotion ? 0 : 0.22,
            solidFallback: false
        )
    }
}

public enum GlassSettingsSidebar {
    /// Existing rows stay first. Filled slots follow, in manifest order.
    public static func rowIDs(existing: [String], slots: [GlassSectionSlot]) -> [String] {
        existing + slots.filter(\.filled).map(\.id)
    }
}

public struct GlassAccessibilityItem: Equatable, Sendable {
    public var label: String
    public var heading: Bool
    public var hidden: Bool

    public init(label: String, heading: Bool, hidden: Bool) {
        self.label = label
        self.heading = heading
        self.hidden = hidden
    }
}

public enum GlassSettingsAccessibility {
    /// A filled slot exposes its title as a heading. An unfilled slot exposes nothing.
    public static func exposure(slots: [GlassSectionSlot]) -> [GlassAccessibilityItem] {
        slots.filter(\.filled).map { GlassAccessibilityItem(label: $0.title, heading: true, hidden: false) }
    }
}

public enum GlassSettingsCheckRunner {
    /// A run past the budget is a timeout. Two timeouts are an infrastructure error.
    public static func attempt(elapsed: TimeInterval, succeeded: Bool, budget: TimeInterval) -> GlassSettingsVerification.Run {
        if elapsed > budget { return .timedOut }
        return .finished(succeeded)
    }

    public static func verdict(firstElapsed: TimeInterval, firstSucceeded: Bool, secondElapsed: TimeInterval?, secondSucceeded: Bool?, budget: TimeInterval) -> GlassSettingsVerification.Verdict {
        let first = attempt(elapsed: firstElapsed, succeeded: firstSucceeded, budget: budget)
        if case .timedOut = first {
            guard let secondElapsed, let secondSucceeded else {
                return GlassSettingsVerification.verdict(attempts: [first])
            }
            let second = attempt(elapsed: secondElapsed, succeeded: secondSucceeded, budget: budget)
            return GlassSettingsVerification.verdict(attempts: [first, second])
        }
        return GlassSettingsVerification.verdict(attempts: [first])
    }
}

public enum GlassSettingsFocus {
    /// Clamps to the sidebar. An empty list stays at 0.
    public static func index(after current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let start = min(max(current, 0), count - 1)
        return min(max(start + delta, 0), count - 1)
    }
}

/// Keys the existing settings surface already stores. Catalog ids are read from the catalog source.
public enum SettingsKeyReachability {
    public static let catalogCount = 212
    public static let outsideCount = 77
    public static let sectionCount = 27
    public static let requiredFingerprint = "42a6fb1152bb4c71"

    public static let outsideKeys: [String] = [
        "showCaptions",
        "showMenuBarIcon",
        "dates.followSystemCalendar",
        "talk.shortcut",
        "notify.calendarLead",
        "notify.reminders",
        "notify.focus",
        "notify.quietSharing",
        "sound.volume",
        "sound.approval",
        "sound.done",
        "sound.todo",
        "sound.voiceStart",
        "sound.voiceStop",
        "sound.voiceDone",
        "sound.voiceError",
        "shortcut.quickTodo",
        "voice.engine",
        "voice.engine.userSelected",
        "voice.engine.auto",
        "voice.ttsProvider",
        "voice.personality",
        "voice.kokoro.voice",
        "voice.kokoro.speed",
        "voice.elevenlabs.quality",
        "voice.openai.voice",
        "voice.gemini.voice",
        "voice.orbStyle",
        "wake.enabled",
        "dictation.autoSwitch",
        "dictation.restoreClipboard",
        "dictation.cueStyle",
        "dictation.cueVolume",
        "dictation.pauseMedia",
        "dictation.engineForVoice",
        "dictation.alwaysType",
        "dictation.typedApps",
        "dictation.microphone",
        "dictation.preview",
        "dictation.mode",
        "polyglot.enabled",
        "polyglot.source",
        "polyglot.target",
        "polyglot.showOriginal",
        "polyglot.size",
        "polyglot.hotkey",
        "keepAwake.display",
        "keepAwake.batteryFloor",
        "keepAwake.endWhenHot",
        "keepAwake.homeMinutes",
        "insomnia.lidClosed",
        "insomnia.freeze",
        "insomnia.hotspotSSID",
        "insomnia.nudge",
        "insomnia.nudgeMinutes",
        "insomnia.mute",
        "insomnia.lowPower",
        "insomnia.minutes",
        "topBar.tabs",
        "topBar.cues",
        "topBar.weatherCity",
        "topBar.celsius",
        "topBar.note",
        "prompter.script",
        "prompter.speed",
        "prompter.voice",
        "prompter.size",
        "prompter.followPresentation",
        "todo.reminders",
        "todo.learning",
        "todo.connection",
        "todo.vaultBookmark",
        "proactive.brief",
        "proactive.nudges",
        "aboutYou.name",
        "present.physicalPointer",
        "drive.autonomy",
    ]

    public static let existingSectionIDs: [String] = [
        "general", "appearance", "notifications", "sounds", "voice", "dictation", "shortcuts",
        "topBar", "todo", "memory", "teleprompter", "agents", "stickies", "routines", "keepAwake",
        "integrations", "assistant", "intelligence", "permissions", "privacy", "interview", "iPhone",
        "diagnostics", "license", "about", "tiling", "shelf",
    ]

    public static func catalogIDs(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            guard line.contains("SettingOption(id:") else { return nil }
            return firstQuotedString(in: String(line))
        }
    }

    public static func gsSectionRawValues(in source: String) -> [String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("enum GSSection:") }) else { return [] }
        var ids: [String] = []
        for line in lines[start...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("var ") { break }
            guard trimmed.hasPrefix("case "), !trimmed.contains("case .") else { continue }
            let rest = trimmed.dropFirst("case ".count)
            ids.append(contentsOf: rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        return ids
    }

    public static func collidingSlotIDs(slotIDs: [String], sectionIDs: [String]) -> [String] {
        let sections = Set(sectionIDs)
        return slotIDs.filter { sections.contains($0) }
    }

    public static func sectionIDs(in settingsViewSource: String) -> [String] {
        let lines = settingsViewSource.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let enumIndex = lines.firstIndex(where: { $0.contains("enum Section: String, CaseIterable, Identifiable") }) else {
            return []
        }
        let tail = lines[enumIndex...]
        guard let caseLine = tail.first(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("case ") && !trimmed.contains("case .")
        }) else { return [] }
        let rest = caseLine.trimmingCharacters(in: .whitespaces).dropFirst("case ".count)
        return rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func reachableKeys(catalogIDs: [String]) -> Set<String> {
        Set(catalogIDs).union(outsideKeys)
    }

    public static func missing(required: Set<String>, present: Set<String>) -> [String] {
        required.subtracting(present).sorted()
    }

    public static func duplicateIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for id in ids where !seen.insert(id).inserted && !duplicates.contains(id) {
            duplicates.append(id)
        }
        return duplicates
    }

    /// FNV-1a 64 of the sorted keys joined by newlines. Order does not change the result.
    public static func fingerprint(_ keys: some Sequence<String>) -> String {
        let blob = Set(keys).sorted().joined(separator: "\n")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in blob.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func firstQuotedString(in line: String) -> String? {
        guard let open = line.firstIndex(of: "\"") else { return nil }
        var index = line.index(after: open)
        var value = ""
        while index < line.endIndex {
            let character = line[index]
            if character == "\\" {
                let next = line.index(after: index)
                guard next < line.endIndex else { return nil }
                value.append(line[next])
                index = line.index(after: next)
                continue
            }
            if character == "\"" { return value }
            value.append(character)
            index = line.index(after: index)
        }
        return nil
    }
}

public enum SettingsWindowCensus {
    public static let productWindowCount = 1

    public static func creations(in source: String) -> Int {
        source.components(separatedBy: "NSWindow(").count - 1
    }
}

public enum GlassSettingsVerification {
    public enum Run: Equatable, Sendable {
        case finished(Bool)
        case timedOut
    }

    public enum Verdict: Equatable, Sendable {
        case passed
        case productFailure
        case infrastructure
    }

    /// A timeout is retried once. A second timeout is an infrastructure error, not a product failure.
    public static func verdict(attempts: [Run]) -> Verdict {
        guard let first = attempts.first else { return .infrastructure }
        switch first {
        case .finished(true):
            return .passed
        case .finished(false):
            return .productFailure
        case .timedOut:
            guard attempts.count > 1 else { return .infrastructure }
            switch attempts[1] {
            case .finished(true):
                return .passed
            case .finished(false):
                return .productFailure
            case .timedOut:
                return .infrastructure
            }
        }
    }
}

public enum GlassSettingsSourceRules {
    public static func forbiddenMarkers(in source: String) -> [String] {
        let markers = ["XCT" + "Skip", "XCTExpect" + "Failure", "withKnown" + "Issue", ".disabled" + "(", "x" + "fail"]
        return markers.filter { source.contains($0) }
    }

    public static func writesUniversalAccess(_ source: String) -> Bool {
        let domain = ["com", "apple", "universalaccess"].joined(separator: ".")
        return source.contains(domain)
    }
}

public enum GlassSettingsAudit {
    public static func keyAndSectionFailures(catalogSource: String, settingsViewSource: String) -> [String] {
        var failures: [String] = []
        let ids = SettingsKeyReachability.catalogIDs(in: catalogSource)
        if ids.count != SettingsKeyReachability.catalogCount {
            failures.append("catalog count \(ids.count)")
        }
        if Set(ids).count != SettingsKeyReachability.catalogCount {
            failures.append("catalog unique \(Set(ids).count)")
        }
        let duplicates = SettingsKeyReachability.duplicateIDs(ids)
        if !duplicates.isEmpty {
            failures.append("duplicate catalog ids \(duplicates.joined(separator: ","))")
        }
        if SettingsKeyReachability.outsideKeys.count != SettingsKeyReachability.outsideCount {
            failures.append("outside count \(SettingsKeyReachability.outsideKeys.count)")
        }
        if !SettingsKeyReachability.duplicateIDs(SettingsKeyReachability.outsideKeys).isEmpty {
            failures.append("duplicate outside keys")
        }
        let reachable = SettingsKeyReachability.reachableKeys(catalogIDs: ids)
        let missingCatalog = SettingsKeyReachability.missing(required: Set(ids), present: reachable)
        if !missingCatalog.isEmpty {
            failures.append("catalog keys missing \(missingCatalog.joined(separator: ","))")
        }
        let missingOutside = SettingsKeyReachability.missing(required: Set(SettingsKeyReachability.outsideKeys), present: reachable)
        if !missingOutside.isEmpty {
            failures.append("outside keys missing \(missingOutside.joined(separator: ","))")
        }
        let fingerprint = SettingsKeyReachability.fingerprint(reachable)
        if fingerprint != SettingsKeyReachability.requiredFingerprint {
            failures.append("fingerprint \(fingerprint)")
        }
        let sections = SettingsKeyReachability.sectionIDs(in: settingsViewSource)
        if sections != SettingsKeyReachability.existingSectionIDs {
            failures.append("sections \(sections)")
        }
        if SettingsKeyReachability.existingSectionIDs.count != SettingsKeyReachability.sectionCount {
            failures.append("section pin \(SettingsKeyReachability.existingSectionIDs.count)")
        }
        let declaredKeys = GlassSectionManifest.slots.reduce(0) { $0 + $1.keys.count }
        if declaredKeys != GlassSectionManifest.newSettingKeyCount {
            failures.append("new key accounting \(GlassSectionManifest.newSettingKeyCount) vs \(declaredKeys)")
        }
        return failures
    }

    public static func manifestFailures() -> [String] {
        var failures: [String] = []
        let slots = GlassSectionManifest.slots
        let expectedIDs = ["glass.media", "glass.general", "glass.portal", "glass.sensory", "glass.battery", "glass.focus", "glass.weather", "glass.lockScreen", "glass.faceID", "glass.accessory", "glass.license", "glass.autoUpdate"]
        let expectedTitles = ["Media", "General", "Portal", "Sensory", "Battery", "Focus", "Weather", "Lock Screen", "Face ID", "Accessory", "License", "Auto-update"]
        if slots.count != 12 { failures.append("slot count \(slots.count)") }
        if slots.map(\.id) != expectedIDs { failures.append("slot ids") }
        if slots.map(\.title) != expectedTitles { failures.append("slot titles") }
        if SettingsKeyReachability.duplicateIDs(slots.map(\.id)).isEmpty == false { failures.append("duplicate slots") }
        let declaredKeys = slots.reduce(0) { $0 + $1.keys.count }
        if declaredKeys != GlassSectionManifest.newSettingKeyCount {
            failures.append("new key accounting \(GlassSectionManifest.newSettingKeyCount) vs \(declaredKeys)")
        }
        let broken = slots.filter { $0.id.trimmingCharacters(in: .whitespaces).isEmpty || $0.title.isEmpty }
        if !broken.isEmpty { failures.append("blank slot") }
        return failures
    }

    public static func propertyFailures() -> [String] {
        var failures: [String] = []
        let universe = (0..<12).map { "k\($0)" }
        for mask in 0..<4096 {
            var required: Set<String> = []
            var present: Set<String> = []
            for bit in 0..<12 {
                let key = universe[bit]
                if mask & (1 << bit) != 0 { required.insert(key) }
                else { present.insert(key) }
            }
            let missing = SettingsKeyReachability.missing(required: required, present: present)
            if missing != required.sorted() {
                failures.append("mask \(mask) missing \(missing)")
                break
            }
            if !SettingsKeyReachability.missing(required: required, present: required).isEmpty {
                failures.append("mask \(mask) present should cover required")
                break
            }
        }
        var mixed = Set(universe)
        mixed.insert("k0")
        if SettingsKeyReachability.missing(required: Set(universe), present: mixed) != [] {
            failures.append("duplicate present changed the difference")
        }
        let shuffled = universe.reversed()
        if SettingsKeyReachability.fingerprint(universe) != SettingsKeyReachability.fingerprint(shuffled) {
            failures.append("fingerprint depends on order")
        }
        if SettingsKeyReachability.missing(required: ["b", "a"], present: ["a"]) != ["b"] {
            failures.append("missing keys are not sorted")
        }
        return failures
    }

    public static func boundaryFailures() -> [String] {
        var failures: [String] = []
        let flags = [false, true]
        for motion in flags {
            for transparency in flags {
                for contrast in flags {
                    let access = GlassSettingsAccess(reduceMotion: motion, reduceTransparency: transparency, increaseContrast: contrast)
                    let material = GlassSettingsMaterialRules.resolve(access)
                    let solid = transparency || contrast
                    if material.solidFallback != solid || material.translucent == solid {
                        failures.append("solid \(motion) \(transparency) \(contrast)")
                    }
                    if material.fillOpacity < 0 || material.fillOpacity > 1 || material.highlightOpacity < 0 || material.highlightOpacity > 1 {
                        failures.append("opacity out of range")
                    }
                    if material.animationDuration < 0 || (motion && material.animationDuration != 0) || (!motion && material.animationDuration == 0) {
                        failures.append("duration \(material.animationDuration)")
                    }
                    if solid && (material.highlightOpacity != 0 || material.depth != 0 || material.fillOpacity != 1) {
                        failures.append("solid fallback still translucent")
                    }
                    if !solid && (material.depth <= 0 || material.highlightOpacity <= 0 || material.fillOpacity >= 1) {
                        failures.append("open material lost depth or highlight")
                    }
                }
            }
        }
        if GlassSettingsFocus.index(after: 0, delta: 1, count: 0) != 0 { failures.append("empty focus") }
        if GlassSettingsFocus.index(after: 5, delta: 1, count: 1) != 0 { failures.append("single focus") }
        if GlassSettingsFocus.index(after: 0, delta: -4, count: 4) != 0 { failures.append("low clamp") }
        if GlassSettingsFocus.index(after: 3, delta: 9, count: 4) != 3 { failures.append("high clamp") }
        if GlassSettingsFocus.index(after: -2, delta: 1, count: 4) != 1 { failures.append("negative index") }
        if !SettingsKeyReachability.catalogIDs(in: "").isEmpty { failures.append("empty catalog") }
        let one = SettingsKeyReachability.catalogIDs(in: "SettingOption(id: \"only.key\", section: .general)")
        if one != ["only.key"] { failures.append("one catalog row \(one)") }
        let escaped = SettingsKeyReachability.catalogIDs(in: "SettingOption(id: \"quote\\\"key\", title: \"x\")")
        if escaped != ["quote\"key"] { failures.append("escaped catalog id \(escaped)") }
        if SettingsKeyReachability.duplicateIDs(["a", "b", "a"]) != ["a"] { failures.append("duplicates") }
        if SettingsKeyReachability.fingerprint([]) != "cbf29ce484222325" { failures.append("empty fingerprint") }
        let synthetic = "enum Section: String, CaseIterable, Identifiable {\n        case alpha, beta\n    }\n"
        if SettingsKeyReachability.sectionIDs(in: synthetic) != ["alpha", "beta"] { failures.append("synthetic sections") }
        if SettingsWindowCensus.creations(in: "let window = NSWindow(contentRect: .zero)") != 1 { failures.append("one creation") }
        if SettingsWindowCensus.creations(in: "no window here") != 0 { failures.append("zero creations") }
        if SettingsWindowCensus.productWindowCount != 1 { failures.append("census") }
        let blank = GlassSectionSlot(id: " ", title: "", filled: false, keys: ["extra"])
        let problems = GlassSectionManifest.slotProblems([blank])
        if !problems.contains("blank id") || !problems.contains("blank title") || !problems.contains("keys while empty") {
            failures.append("blank slot problems \(problems)")
        }
        if !GlassSectionManifest.slotProblems(GlassSectionManifest.slots).isEmpty {
            failures.append("live slots are not valid placeholders")
        }
        return failures
    }

    public static func timeoutFailures() -> [String] {
        var failures: [String] = []
        typealias Run = GlassSettingsVerification.Run
        let cases: [([Run], GlassSettingsVerification.Verdict)] = [
            ([], .infrastructure),
            ([.finished(true)], .passed),
            ([.finished(false)], .productFailure),
            ([.timedOut], .infrastructure),
            ([.timedOut, .finished(true)], .passed),
            ([.timedOut, .finished(false)], .productFailure),
            ([.timedOut, .timedOut], .infrastructure),
            ([.finished(true), .timedOut], .passed),
            ([.finished(false), .finished(true)], .productFailure),
            ([.timedOut, .timedOut, .finished(true)], .infrastructure),
        ]
        for (attempts, expected) in cases {
            let verdict = GlassSettingsVerification.verdict(attempts: attempts)
            if verdict != expected { failures.append("verdict \(attempts) -> \(verdict)") }
        }
        let runs: [Run] = [.finished(true), .finished(false), .timedOut]
        for first in runs {
            for second in runs {
                for third in runs {
                    let verdict = GlassSettingsVerification.verdict(attempts: [first, second, third])
                    if first == .finished(false) && verdict != .productFailure {
                        failures.append("failure relabeled")
                    }
                    if first == .timedOut && second == .timedOut && verdict != .infrastructure {
                        failures.append("second timeout was not infrastructure")
                    }
                    if case .timedOut = first, case .timedOut = second, verdict == .productFailure {
                        failures.append("timeout counted as a product failure")
                    }
                }
            }
        }
        return failures
    }

    public static func windowFailures(windowSource: String, chromeSource: String) -> [String] {
        var failures: [String] = []
        let windows = SettingsWindowCensus.creations(in: windowSource)
        if windows != SettingsWindowCensus.productWindowCount {
            failures.append("settings windows \(windows)")
        }
        if SettingsWindowCensus.creations(in: chromeSource) != 0 {
            failures.append("chrome opens a window")
        }
        if !windowSource.contains("title = \"Zeus Settings\"") {
            failures.append("window title")
        }
        return failures
    }

    public static func collisionFailures(windowSource: String) -> [String] {
        let sections = SettingsKeyReachability.gsSectionRawValues(in: windowSource)
        if sections.isEmpty { return ["sidebar sections were not read"] }
        let hits = SettingsKeyReachability.collidingSlotIDs(
            slotIDs: GlassSectionManifest.slots.map(\.id),
            sectionIDs: sections
        )
        if !hits.isEmpty { return ["slot ids collide with sidebar rows \(hits.joined(separator: ","))"] }
        let bare = SettingsKeyReachability.collidingSlotIDs(slotIDs: ["general", "license"], sectionIDs: sections)
        if bare != ["general", "license"] { return ["collision sample \(bare)"] }
        let namespaced = SettingsKeyReachability.collidingSlotIDs(slotIDs: ["glass.general", "glass.license"], sectionIDs: sections)
        if !namespaced.isEmpty { return ["namespaced ids collided"] }
        return []
    }

    public static func inspectorDeltaFailures(windowSource: String) -> [String] {
        var failures: [String] = []
        let flipped = GlassSectionManifest.providers.map { provider -> GlassSectionSlot in
            let slot = provider.descriptor
            guard slot.id == "glass.media" else { return slot }
            return GlassSectionSlot(id: slot.id, title: slot.title, filled: true, keys: slot.keys, order: slot.order, enabled: slot.enabled, placement: slot.placement)
        }
        let shownRows = SettingsSectionRegistry.sections(slots: flipped, includePhone: false)
        if shownRows.last?.id != SettingsSectionRegistry.topbarID { failures.append("filled topbar tab did not add the Topbar row") }
        if shownRows.contains(where: { $0.id == "glass.media" }) { failures.append("a topbar tab became its own sidebar row") }
        if !SettingsSectionRegistry.search("Topbar", in: shownRows).contains(where: { $0.id == SettingsSectionRegistry.topbarID }) { failures.append("Topbar missing from search") }
        if !shownRows.map(\.accessibilityLabel).contains("Topbar") { failures.append("Topbar missing from voiceover order") }
        let tabs = GlassSectionManifest.topbarTabs(in: flipped)
        if !tabs.contains(where: { $0.id == "glass.media" }) { failures.append("media tab missing from the host") }
        if tabs.contains(where: { !$0.filled }) { failures.append("an unfilled tab appeared") }
        if shownRows.filter({ $0.id == SettingsSectionRegistry.topbarID }).count != 1 { failures.append("more than one Topbar row") }
        if GlassSettingsMetrics.controlRow != 52 || GlassSettingsMetrics.helperLine != 16 || GlassSettingsMetrics.panelPadding != 32 || GlassSettingsMetrics.cardSpacing != 28 {
            failures.append("metrics")
        }
        let window = windowSource
        var state = SettingsSelectionState.section("settings.general")
        state = SettingsSelectionRules.selectingSlot("glass.probe", current: state)
        if state != .slot("glass.probe") { failures.append("slot left the section selected") }
        state = SettingsSelectionRules.selectingSection("settings.sounds", current: state)
        if state != .section("settings.sounds") { failures.append("section left the slot selected") }
        if SettingsSelectionRules.selectingSlot("  ", current: state) != state { failures.append("blank slot changed the selection") }
        for count in [21, 22, 23, 34] where SettingsSidebarLayout.rowMetrics(rowCount: count).height != 30 {
            failures.append("sidebar row \(count) is not 30 points")
        }
        if SettingsSidebarLayout.bottom(rowCount: 34) <= SettingsSidebarLayout.versionY { failures.append("tall sidebar does not scroll") }
        if window.contains("rowMetrics(rowCount: GSSection.shown.count)") { failures.append("sidebar metrics ignore filled rows") }
        if !window.contains("enum SettingsSelection") || !window.contains("case slot(SlotID)") || !window.contains("case topbar") || window.contains("var glassSlotID") {
            failures.append("selection is not one value")
        }
        if !window.contains("includePhone: GSSection.iPhonePairingAvailable") { failures.append("phone row is not wired") }
        let shown = SettingsSectionRegistry.sections(slots: [], includePhone: true).map(\.title)
        if let engine = shown.firstIndex(of: "Engine"), shown[engine + 1] != "iPhone" { failures.append("phone row missing") }
        let first = GlassSectionSlot(id: "glass.dup", title: "First", filled: true, keys: [], order: 10)
        let second = GlassSectionSlot(id: "glass.dup", title: "Second", filled: true, keys: [], order: 11)
        let later = GlassSectionSlot(id: "glass.later", title: "Later", filled: true, keys: [], order: 12)
        let earlier = GlassSectionSlot(id: "glass.earlier", title: "Earlier", filled: true, keys: [], order: 9)
        let rows = SettingsSectionRegistry.orderedSlots([later, second, first, earlier])
        if rows.filter({ $0.id == "glass.dup" }).count != 1 { failures.append("duplicate slot kept") }
        if rows.suffix(3).map(\.id) != ["glass.earlier", "glass.dup", "glass.later"] { failures.append("slot order") }
        return failures
    }

    public static func registryFailures() -> [String] {
        var failures: [String] = []
        let existing = SettingsSectionRegistry.existing
        if Set(existing.map(\.id)).count != existing.count { failures.append("duplicate existing ids") }
        if existing.map(\.order) != Array(0..<existing.count) { failures.append("existing orders are not 0...n") }
        if existing.contains(where: { $0.placeholder != nil }) { failures.append("an existing section has a placeholder") }
        let again = SettingsSectionRegistry.sections(slots: [])
        if again != existing { failures.append("empty slot list changed the existing order") }
        let synthetic = GlassSectionSlot(id: "glass.synthetic", title: "Synthetic", filled: true, keys: [], placement: .topbarTab(0))
        let hidden = GlassSectionSlot(id: "glass.hidden", title: "Hidden", filled: false, keys: [], placement: .topbarTab(1))
        let withSynthetic = SettingsSectionRegistry.sections(slots: [hidden, synthetic])
        if withSynthetic.prefix(existing.count).map(\.id) != existing.map(\.id) { failures.append("existing order changed") }
        if withSynthetic.last?.id != SettingsSectionRegistry.topbarID { failures.append("filled topbar tab did not append") }
        if withSynthetic.contains(where: { $0.id == "glass.hidden" || $0.id == "glass.synthetic" }) { failures.append("a tab appeared as its own row") }
        if SettingsSectionRegistry.existing.contains(where: { $0.id == "glass.synthetic" }) { failures.append("synthetic id was written into the registry") }
        let repeated = SettingsSectionRegistry.sections(slots: [synthetic])
        if repeated != SettingsSectionRegistry.sections(slots: [synthetic]) { failures.append("order is not stable") }
        let found = SettingsSectionRegistry.search("License", in: existing)
        if found.first?.id != SettingsSectionRegistry.id(for: "license") { failures.append("search left registry order") }
        if SettingsSectionRegistry.search("u", in: existing).first?.title != "Sounds" { failures.append("search order") }
        let liveIDs = Set(SettingsSectionRegistry.live.map(\.id))
        for slot in GlassSectionManifest.slots where !slot.filled && liveIDs.contains(slot.id) {
            failures.append("unfilled live slot \(slot.id)")
        }
        let allIDs = existing.map(\.id) + GlassSectionManifest.slots.map(\.id)
        if Set(allIDs).count != allIDs.count { failures.append("registry ids are not unique") }
        return failures
    }

    public static func sidebarFailures() -> [String] {
        let existing = ["general", "appearance", "license"]
        let slots = [
            GlassSectionSlot(id: "glass.synthetic", title: "Synthetic", filled: true, keys: []),
            GlassSectionSlot(id: "glass.hidden", title: "Hidden", filled: false, keys: []),
        ]
        let rows = GlassSettingsSidebar.rowIDs(existing: existing, slots: slots)
        if rows != existing + ["glass.synthetic"] { return ["sidebar rows \(rows)"] }
        if Array(rows.prefix(existing.count)) != existing { return ["existing sidebar rows changed"] }
        return []
    }

    public static func accessibilityFailures() -> [String] {
        let hidden = GlassSectionSlot(id: "glass.hidden", title: "Hidden", filled: false, keys: [])
        let synthetic = GlassSectionSlot(id: "glass.synthetic", title: "Synthetic title", filled: true, keys: [])
        let items = GlassSettingsAccessibility.exposure(slots: [hidden, synthetic])
        let expected = [GlassAccessibilityItem(label: "Synthetic title", heading: true, hidden: false)]
        if items != expected { return ["accessibility exposure \(items)"] }
        return []
    }

    public static func hungCheckFailures() -> [String] {
        let hung = GlassSettingsCheckRunner.verdict(
            firstElapsed: 31, firstSucceeded: false, secondElapsed: 31, secondSucceeded: false, budget: 30
        )
        if hung != .infrastructure { return ["a second timeout was \(hung)"] }
        let recovered = GlassSettingsCheckRunner.verdict(
            firstElapsed: 31, firstSucceeded: false, secondElapsed: 1, secondSucceeded: true, budget: 30
        )
        if recovered != .passed { return ["a retry that finished was \(recovered)"] }
        let product = GlassSettingsCheckRunner.verdict(
            firstElapsed: 1, firstSucceeded: false, secondElapsed: nil, secondSucceeded: nil, budget: 30
        )
        if product != .productFailure { return ["a finished failure was \(product)"] }
        return []
    }

    public static func sourceRuleFailures(_ sources: [String]) -> [String] {
        var failures: [String] = []
        for source in sources {
            let markers = GlassSettingsSourceRules.forbiddenMarkers(in: source)
            if !markers.isEmpty { failures.append("disabled test marker \(markers.joined(separator: ","))") }
            if GlassSettingsSourceRules.writesUniversalAccess(source) {
                failures.append("writes the accessibility preference domain")
            }
        }
        return failures
    }
}
