import Foundation

/// One earbud setting, off unless a person turns it on. An imported file cannot turn it on.
public enum BatteryEarbudSetting {
    public static let key = "battery.earbuds"
    public static let defaultEnabled = false

    public enum Origin: Equatable, Sendable {
        case person
        case restore
        case importFile
    }

    public static func enabled(requested: Bool, origin: Origin, currently: Bool) -> Bool {
        switch origin {
        case .person, .restore: return requested
        case .importFile:
            _ = currently
            return false
        }
    }
}

public enum EarbudPart: String, CaseIterable, Equatable, Sendable {
    case left
    case right
    case cradle
    case single

    public var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .cradle: "Case"
        case .single: "Battery"
        }
    }
}

public enum EarbudLevel: Equatable, Sendable {
    case unknown
    case fresh(Int)
    case lastKnown(Int)

    public var percent: Int? {
        switch self {
        case .unknown: nil
        case .fresh(let value), .lastKnown(let value): (1...100).contains(value) ? value : nil
        }
    }
}

public enum EarbudLevelReading {
    public static func valid(_ raw: Int?) -> Int? {
        guard let raw, (1...100).contains(raw) else { return nil }
        return raw
    }

    public static func interpret(_ raw: Int?) -> EarbudLevel {
        guard let percent = valid(raw) else { return .unknown }
        return .fresh(percent)
    }
}

public enum EarbudLevelText {
    public static func display(_ level: EarbudLevel) -> String {
        switch level {
        case .unknown:
            return "unknown"
        case .fresh(let value), .lastKnown(let value):
            guard (1...100).contains(value) else { return "unknown" }
            return "\(value)%"
        }
    }
}

public enum EarbudParts {
    /// Two buds answer as left, right, and case. One piece answers as a single level. Anything else is hidden.
    public static func layout(answering: Set<EarbudPart>) -> [EarbudPart] {
        if answering.contains(.left) || answering.contains(.right) { return [.left, .right, .cradle] }
        if answering.contains(.single) { return [.single] }
        return []
    }
}

public struct EarbudBatteryBook: Equatable, Sendable {
    public struct Memory: Equatable, Sendable {
        public var percent: Int
        public var at: TimeInterval

        public init(percent: Int, at: TimeInterval) {
            self.percent = percent
            self.at = at
        }
    }

    public var memory: [EarbudPart: Memory]
    public static let lastKnownLifetime: TimeInterval = 1800

    public init(memory: [EarbudPart: Memory] = [:]) {
        self.memory = memory
    }

    public func merging(_ raw: [EarbudPart: Int?], now: TimeInterval) -> EarbudBatteryBook {
        var copy = self
        for (part, value) in raw {
            guard let percent = EarbudLevelReading.valid(value) else { continue }
            copy.memory[part] = Memory(percent: percent, at: now)
        }
        return copy
    }

    public func level(_ part: EarbudPart, now: TimeInterval) -> EarbudLevel {
        guard let stored = memory[part] else { return .unknown }
        let age = now - stored.at
        if age <= 0 { return .fresh(stored.percent) }
        if age <= Self.lastKnownLifetime { return .lastKnown(stored.percent) }
        return .unknown
    }
}

public enum BluetoothAccess: Equatable, Sendable {
    case notAsked
    case allowed
    case denied
    case restricted
}

/// Off, waiting, prompting, denied, watching, unavailable, or paused. The prompt has one door.
public enum EarbudConsent {
    public enum Phase: Equatable, Sendable {
        case off
        case waiting
        case prompting
        case denied
        case watching
        case unavailable
        case paused
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase

        public init(phase: Phase = .off) {
            self.phase = phase
        }
    }

    public enum Event: Equatable, Sendable {
        case restore(enabled: Bool, access: BluetoothAccess)
        case userSet(enabled: Bool, access: BluetoothAccess)
        case accessAnswered(BluetoothAccess)
        case routeChecked(open: Bool)
        case session(active: Bool, access: BluetoothAccess)
    }

    public enum Effect: Equatable, Sendable {
        case promptForBluetooth
        case stopWatching
        case readStatus
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .restore(let enabled, let access):
            guard enabled else { return (State(phase: .off), []) }
            switch access {
            case .allowed: return (State(phase: .watching), [.readStatus])
            case .notAsked: return (State(phase: .waiting), [])
            case .denied, .restricted: return (State(phase: .denied), [])
            }
        case .userSet(let enabled, let access):
            guard enabled else {
                if state.phase == .off { return (state, []) }
                return (State(phase: .off), [.stopWatching])
            }
            if state.phase == .prompting { return (state, []) }
            if state.phase == .watching, access == .allowed { return (state, []) }
            return enter(access, fromUser: true)
        case .accessAnswered(let access):
            guard state.phase == .prompting else { return (state, []) }
            return enter(access, fromUser: false)
        case .routeChecked(let open):
            switch state.phase {
            case .watching where !open:
                return (State(phase: .unavailable), [.stopWatching])
            case .unavailable where open:
                return (State(phase: .watching), [.readStatus])
            default:
                return (state, [])
            }
        case .session(let active, let access):
            if !active {
                if state.phase == .off || state.phase == .paused { return (state, []) }
                return (State(phase: .paused), [.stopWatching])
            }
            guard state.phase == .paused else { return (state, []) }
            switch access {
            case .allowed: return (State(phase: .watching), [.readStatus])
            case .notAsked: return (State(phase: .waiting), [])
            case .denied, .restricted: return (State(phase: .denied), [])
            }
        }
    }

    private static func enter(_ access: BluetoothAccess, fromUser: Bool) -> (State, [Effect]) {
        switch access {
        case .allowed: return (State(phase: .watching), [.readStatus])
        case .notAsked:
            if fromUser { return (State(phase: .prompting), [.promptForBluetooth]) }
            return (State(phase: .waiting), [])
        case .denied, .restricted: return (State(phase: .denied), [])
        }
    }
}

/// Private names leave this file only when the setting is on and Bluetooth is already allowed.
public enum EarbudPrivateSymbols {
    public static func batteryKeyNames(settingEnabled: Bool, accessAllowed: Bool) -> [String] {
        guard settingEnabled, accessAllowed else { return [] }
        return ["batteryPercentLeft", "batteryPercentRight", "batteryPercentCase", "batteryPercentSingle"]
    }

    public static func listeningModeSelectors(settingEnabled: Bool) -> [UInt32] {
        guard settingEnabled else { return [] }
        return [0x6c73746d, 0x6c736d73]
    }
}

public struct EarbudBatteryReading: Equatable, Sendable {
    public var routeOpen: Bool
    public var values: [EarbudPart: Int?]
    public var answering: Set<EarbudPart>

    public init(routeOpen: Bool, values: [EarbudPart: Int?], answering: Set<EarbudPart>) {
        self.routeOpen = routeOpen
        self.values = values
        self.answering = answering
    }
}

public enum ListeningMode: Equatable, Sendable, CaseIterable {
    case off
    case noiseCancelling
    case transparency
    case adaptive

    public var title: String {
        switch self {
        case .off: "Off"
        case .noiseCancelling: "Noise cancelling"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        }
    }

    public var isChoice: Bool { self != .adaptive }
}

public struct ListeningModeSample: Equatable, Sendable {
    public var symbolPresent: Bool
    public var byteSize: Int
    public var rawMode: UInt32?
    public var rawMask: UInt32?
    public var bluetoothTransport: Bool

    public init(symbolPresent: Bool, byteSize: Int, rawMode: UInt32?, rawMask: UInt32?, bluetoothTransport: Bool) {
        self.symbolPresent = symbolPresent
        self.byteSize = byteSize
        self.rawMode = rawMode
        self.rawMask = rawMask
        self.bluetoothTransport = bluetoothTransport
    }
}

public struct ListeningModeChoice: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case available
        case refused
        case selected
    }

    public var mode: ListeningMode
    public var state: State

    public init(mode: ListeningMode, state: State) {
        self.mode = mode
        self.state = state
    }
}

public enum ListeningModeRow: Equatable, Sendable {
    case hidden
    case shown(current: ListeningMode, choices: [ListeningModeChoice])
}

public enum ListeningModeRelease {
    public static let verifiedMajor = 27
    public static let verifiedMinor = 2

    public static func allows(_ major: Int, _ minor: Int) -> Bool {
        if major != verifiedMajor { return major > verifiedMajor }
        return minor >= verifiedMinor
    }
}

public enum ListeningModeCode {
    public static func mode(_ raw: UInt32) -> ListeningMode? {
        switch raw {
        case 1: .off
        case 2: .noiseCancelling
        case 3: .transparency
        case 4: .adaptive
        default: nil
        }
    }

    public static func code(_ mode: ListeningMode) -> UInt32 {
        switch mode {
        case .off: 1
        case .noiseCancelling: 2
        case .transparency: 3
        case .adaptive: 4
        }
    }
}

public enum ListeningModeBinding {
    public static func row(_ sample: ListeningModeSample) -> ListeningModeRow {
        guard sample.symbolPresent, sample.byteSize == 4, sample.bluetoothTransport,
              let raw = sample.rawMode, let current = ListeningModeCode.mode(raw),
              let choices = choices(rawMask: sample.rawMask, current: current) else { return .hidden }
        return .shown(current: current, choices: choices)
    }

    public static func choices(rawMask: UInt32?, current: ListeningMode) -> [ListeningModeChoice]? {
        guard let rawMask, bitAgrees(rawMask, current) else { return nil }
        var modes: [ListeningMode] = [.off]
        if rawMask & 1 != 0 { modes.append(.noiseCancelling) }
        if rawMask & 2 != 0 { modes.append(.transparency) }
        guard modes.count >= 2 else { return nil }
        return modes.map { mode in
            ListeningModeChoice(mode: mode, state: mode == current ? .selected : .available)
        }
    }

    private static func bitAgrees(_ mask: UInt32, _ current: ListeningMode) -> Bool {
        switch current {
        case .off: true
        case .noiseCancelling: mask & 1 != 0
        case .transparency: mask & 2 != 0
        case .adaptive: mask & 4 != 0
        }
    }
}

public enum ListeningModeCommit: Equatable, Sendable {
    case hidden
    case unchanged
    case shown(ListeningMode)
    case refused(asked: ListeningMode, read: ListeningMode)
}

public enum ListeningModeEditor {
    /// Writes once, then reads back. The shown value is the value that was read.
    public static func set<Probe: EarbudProbe>(_ asked: ListeningMode, gateOpen: Bool, releaseMajor: Int, releaseMinor: Int, probe: inout Probe) -> ListeningModeCommit {
        guard gateOpen, ListeningModeRelease.allows(releaseMajor, releaseMinor) else { return .hidden }
        let selectors = EarbudPrivateSymbols.listeningModeSelectors(settingEnabled: true)
        let currentSample = probe.listeningMode(selectors: selectors)
        guard case .shown(let current, let choices) = ListeningModeBinding.row(currentSample) else { return .hidden }
        guard asked.isChoice, asked != current, choices.contains(where: { $0.mode == asked && $0.state != .refused }) else {
            return .unchanged
        }
        _ = probe.writeListeningMode(asked, selectors: selectors)
        let readBack = probe.listeningMode(selectors: selectors)
        if let mode = shownMode(readBack), mode == asked { return .shown(mode) }
        let second = probe.listeningMode(selectors: selectors)
        guard let mode = shownMode(second) ?? second.rawMode.flatMap(ListeningModeCode.mode) else { return .hidden }
        if mode == asked { return .shown(mode) }
        return .refused(asked: asked, read: mode)
    }

    private static func shownMode(_ sample: ListeningModeSample) -> ListeningMode? {
        guard case .shown(let current, _) = ListeningModeBinding.row(sample) else { return nil }
        return current
    }
}

public protocol EarbudProbe: Sendable {
    mutating func battery(keys: [String]) -> EarbudBatteryReading
    mutating func listeningMode(selectors: [UInt32]) -> ListeningModeSample
    mutating func writeListeningMode(_ mode: ListeningMode, selectors: [UInt32]) -> ListeningModeSample
}

/// What the Accessory section will read. Levels are unknown rather than zero, and missing controls stay hidden.
public struct EarbudStatusReport: Equatable, Sendable {
    public var levels: [EarbudPart: EarbudLevel]
    public var visibleParts: [EarbudPart]
    public var mode: ListeningModeRow
    public var consultedPrivateKeys: Bool
    public var accessibilitySummary: String

    public init(levels: [EarbudPart: EarbudLevel], visibleParts: [EarbudPart], mode: ListeningModeRow, consultedPrivateKeys: Bool, accessibilitySummary: String) {
        self.levels = levels
        self.visibleParts = visibleParts
        self.mode = mode
        self.consultedPrivateKeys = consultedPrivateKeys
        self.accessibilitySummary = accessibilitySummary
    }

    public static let closed = EarbudStatusReport(levels: [:], visibleParts: [], mode: .hidden, consultedPrivateKeys: false, accessibilitySummary: "")
}

public struct EarbudStatusInput: Equatable, Sendable {
    public var enabled: Bool
    public var access: BluetoothAccess
    public var sessionActive: Bool
    public var now: TimeInterval
    public var releaseMajor: Int
    public var releaseMinor: Int
    public var book: EarbudBatteryBook

    public init(enabled: Bool, access: BluetoothAccess, sessionActive: Bool, now: TimeInterval, releaseMajor: Int, releaseMinor: Int, book: EarbudBatteryBook) {
        self.enabled = enabled
        self.access = access
        self.sessionActive = sessionActive
        self.now = now
        self.releaseMajor = releaseMajor
        self.releaseMinor = releaseMinor
        self.book = book
    }
}

public struct EarbudEvaluation: Equatable, Sendable {
    public var report: EarbudStatusReport
    public var book: EarbudBatteryBook

    public init(report: EarbudStatusReport, book: EarbudBatteryBook) {
        self.report = report
        self.book = book
    }
}

public protocol EarbudStatusSource: Sendable {
    func evaluate<Probe: EarbudProbe>(_ input: EarbudStatusInput, probe: inout Probe) -> EarbudEvaluation
}

public struct GuardedEarbudStatusSource: EarbudStatusSource {
    public init() {}

    public func evaluate<Probe: EarbudProbe>(_ input: EarbudStatusInput, probe: inout Probe) -> EarbudEvaluation {
        guard input.enabled else {
            return EarbudEvaluation(report: .closed, book: EarbudBatteryBook())
        }
        guard input.sessionActive else {
            return EarbudEvaluation(report: .closed, book: input.book)
        }
        if input.access == .notAsked {
            return EarbudEvaluation(report: .closed, book: input.book)
        }

        var consulted = false
        var book = input.book
        var levels: [EarbudPart: EarbudLevel] = [:]
        var visible: [EarbudPart] = []
        if input.access == .allowed {
            let keys = EarbudPrivateSymbols.batteryKeyNames(settingEnabled: true, accessAllowed: true)
            let reading = probe.battery(keys: keys)
            consulted = true
            if reading.routeOpen {
                book = book.merging(reading.values, now: input.now)
                visible = EarbudParts.layout(answering: reading.answering)
                for part in visible {
                    levels[part] = book.level(part, now: input.now)
                }
            }
        }

        var mode: ListeningModeRow = .hidden
        if ListeningModeRelease.allows(input.releaseMajor, input.releaseMinor) {
            let selectors = EarbudPrivateSymbols.listeningModeSelectors(settingEnabled: true)
            let sample = probe.listeningMode(selectors: selectors)
            consulted = true
            mode = ListeningModeBinding.row(sample)
        }
        let summary = visible.map { part in
            "\(part.title) \(EarbudLevelText.display(levels[part] ?? .unknown))"
        }.joined(separator: ". ")
        let report = EarbudStatusReport(
            levels: levels,
            visibleParts: visible,
            mode: mode,
            consultedPrivateKeys: consulted,
            accessibilitySummary: summary
        )
        return EarbudEvaluation(report: report, book: book)
    }
}
