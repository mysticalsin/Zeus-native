import Foundation

public struct AccessoryChargeDisplay: Equatable, Sendable {
    public var left: String
    public var right: String
    public var caseText: String
    public var summary: String

    public init(left: String, right: String, caseText: String, summary: String) {
        self.left = left
        self.right = right
        self.caseText = caseText
        self.summary = summary
    }
}

public struct AccessoryChargeReading: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseCharge: Int?
    public var known: Bool

    public init(left: Int?, right: Int?, caseCharge: Int?, known: Bool) {
        self.left = left
        self.right = right
        self.caseCharge = caseCharge
        self.known = known
    }

    public var display: AccessoryChargeDisplay {
        func cell(_ value: Int?) -> String {
            guard known, let value, (0...100).contains(value) else { return "Unknown" }
            return "\(value)%"
        }
        let leftText = cell(left)
        let rightText = cell(right)
        let caseText = cell(caseCharge)
        let parts = [("Left", leftText), ("Right", rightText), ("Case", caseText)].filter { $0.1 != "Unknown" }
        let summary = parts.isEmpty ? "Unknown" : parts.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        return AccessoryChargeDisplay(left: leftText, right: rightText, caseText: caseText, summary: summary)
    }

    var cleared: AccessoryChargeReading {
        guard known else { return AccessoryChargeReading(left: nil, right: nil, caseCharge: nil, known: false) }
        func kept(_ value: Int?) -> Int? {
            guard let value, (0...100).contains(value) else { return nil }
            return value
        }
        return AccessoryChargeReading(left: kept(left), right: kept(right), caseCharge: kept(caseCharge), known: true)
    }
}

public struct AccessoryConnectInput: Equatable, Sendable {
    public var id: String
    public var name: String
    public var connected: Bool
    public var charge: AccessoryChargeReading
    public var listeningMode: String?

    public init(id: String, name: String, connected: Bool, charge: AccessoryChargeReading, listeningMode: String?) {
        self.id = id
        self.name = name
        self.connected = connected
        self.charge = charge
        self.listeningMode = listeningMode
    }

    public static let preview = AccessoryConnectInput(
        id: "preview",
        name: "Earbuds",
        connected: true,
        charge: AccessoryChargeReading(left: 72, right: 55, caseCharge: 40, known: true),
        listeningMode: nil
    )

    public var sanitized: AccessoryConnectInput? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connected, !trimmedID.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = listeningMode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AccessoryConnectInput(
            id: trimmedID,
            name: trimmedName.isEmpty ? "Earbuds" : trimmedName,
            connected: true,
            charge: charge.cleared,
            listeningMode: mode.isEmpty ? nil : String(mode.prefix(40))
        )
    }
}

public struct AccessoryOverlayGate: Equatable, Sendable {
    public var connectEnabled: Bool
    public var style: AccessoryOverlayStyle
    public var reduceMotion: Bool

    public init(connectEnabled: Bool, style: AccessoryOverlayStyle, reduceMotion: Bool) {
        self.connectEnabled = connectEnabled
        self.style = style
        self.reduceMotion = reduceMotion
    }

    public static let closed = AccessoryOverlayGate(connectEnabled: false, style: .off, reduceMotion: false)

    public var admits: Bool { connectEnabled && style != .off }

    public var duration: Double { reduceMotion ? 0 : MotionTokens.crossfadeDuration }
}

public struct AccessoryOverlayContent: Equatable, Sendable {
    public var input: AccessoryConnectInput
    public var style: AccessoryOverlayStyle
    public var duration: Double
    public var title: String
    public var lines: [String]
    public var accessibilityLabel: String
    public var showsListeningMode: Bool

    public init(input: AccessoryConnectInput, style: AccessoryOverlayStyle, duration: Double, title: String, lines: [String], accessibilityLabel: String, showsListeningMode: Bool) {
        self.input = input
        self.style = style
        self.duration = duration
        self.title = title
        self.lines = lines
        self.accessibilityLabel = accessibilityLabel
        self.showsListeningMode = showsListeningMode
    }

    public static func make(_ input: AccessoryConnectInput, gate: AccessoryOverlayGate) -> AccessoryOverlayContent {
        let display = input.charge.display
        var lines: [String]
        switch gate.style {
        case .off, .compact:
            lines = [display.summary]
        case .split:
            lines = ["Left \(display.left)", "Right \(display.right)", "Case \(display.caseText)"]
        }
        if let mode = input.listeningMode { lines.append(mode) }
        return AccessoryOverlayContent(
            input: input,
            style: gate.style == .off ? .compact : gate.style,
            duration: gate.duration,
            title: input.name,
            lines: lines,
            accessibilityLabel: "\(input.name), \(display.summary)",
            showsListeningMode: input.listeningMode != nil
        )
    }
}

public enum AccessoryConnectOverlayPhase: Equatable, Sendable {
    case closed
    case armed
    case appearing(AccessoryOverlayContent)
    case visible(AccessoryOverlayContent)
    case dismissing(AccessoryOverlayContent)

    public var content: AccessoryOverlayContent? {
        switch self {
        case .closed, .armed: nil
        case .appearing(let content), .visible(let content), .dismissing(let content): content
        }
    }
}

public enum AccessoryConnectOverlayEvent: Equatable, Sendable {
    case gate(AccessoryOverlayGate)
    case connected(AccessoryConnectInput)
    case disconnected
    case appearFinished
    case dismiss
    case dismissFinished
}

public enum AccessoryOverlayEffect: Equatable, Sendable {
    case animateIn(Double)
    case animateOut(Double)
    case showNow
    case hideNow
}

public struct AccessoryConnectOverlayMachine: Equatable, Sendable {
    public private(set) var phase: AccessoryConnectOverlayPhase
    public private(set) var gate: AccessoryOverlayGate
    public private(set) var suppressedID: String?
    public private(set) var latched: AccessoryConnectInput?

    public init(gate: AccessoryOverlayGate = .closed) {
        self.gate = gate
        self.phase = gate.admits ? .armed : .closed
    }

    public mutating func handle(_ event: AccessoryConnectOverlayEvent) -> [AccessoryOverlayEffect] {
        switch event {
        case .gate(let next):
            return apply(next)
        case .connected(let input):
            return connect(input)
        case .disconnected:
            return disconnect()
        case .appearFinished:
            guard case .appearing(let content) = phase else { return [] }
            phase = .visible(content)
            return []
        case .dismiss:
            return dismiss()
        case .dismissFinished:
            return finishDismiss()
        }
    }

    private mutating func apply(_ next: AccessoryOverlayGate) -> [AccessoryOverlayEffect] {
        let previous = gate
        gate = next
        if case .dismissing = phase, next.reduceMotion, !previous.reduceMotion {
            phase = next.admits ? .armed : .closed
            return [.hideNow]
        }
        if case .appearing(var content) = phase, next.reduceMotion, !previous.reduceMotion, next.admits {
            content = retint(content)
            phase = .visible(content)
            return [.showNow]
        }
        if !next.admits {
            switch phase {
            case .closed:
                return []
            case .armed:
                phase = .closed
                return []
            case .appearing, .visible:
                guard let content = phase.content else {
                    phase = .closed
                    return []
                }
                if next.reduceMotion {
                    phase = .closed
                    return [.hideNow]
                }
                phase = .dismissing(content)
                return [.animateOut(content.duration)]
            case .dismissing:
                return []
            }
        }
        switch phase {
        case .closed:
            phase = .armed
            return []
        case .armed, .dismissing:
            return []
        case .appearing(var content):
            content = retint(content)
            phase = .appearing(content)
            return []
        case .visible(var content):
            content = retint(content)
            phase = .visible(content)
            return []
        }
    }

    private func retint(_ content: AccessoryOverlayContent) -> AccessoryOverlayContent {
        AccessoryOverlayContent.make(content.input, gate: gate)
    }

    private mutating func connect(_ input: AccessoryConnectInput) -> [AccessoryOverlayEffect] {
        guard let clean = input.sanitized else { return [] }
        latched = clean
        guard gate.admits, suppressedID != clean.id else { return [] }
        let content = AccessoryOverlayContent.make(clean, gate: gate)
        switch phase {
        case .closed:
            return []
        case .armed:
            if gate.reduceMotion {
                phase = .visible(content)
                return [.showNow]
            }
            phase = .appearing(content)
            return [.animateIn(gate.duration)]
        case .appearing:
            phase = .appearing(content)
            return []
        case .visible:
            phase = .visible(content)
            return []
        case .dismissing:
            return []
        }
    }

    private mutating func disconnect() -> [AccessoryOverlayEffect] {
        suppressedID = nil
        latched = nil
        switch phase {
        case .closed, .armed, .dismissing:
            return []
        case .appearing, .visible:
            guard let content = phase.content else { return [] }
            if gate.reduceMotion {
                phase = gate.admits ? .armed : .closed
                return [.hideNow]
            }
            phase = .dismissing(content)
            return [.animateOut(gate.duration)]
        }
    }

    private mutating func dismiss() -> [AccessoryOverlayEffect] {
        guard let content = phase.content else { return [] }
        switch phase {
        case .appearing, .visible:
            suppressedID = content.input.id
            if gate.reduceMotion {
                phase = gate.admits ? .armed : .closed
                return [.hideNow]
            }
            phase = .dismissing(content)
            return [.animateOut(gate.duration)]
        case .closed, .armed, .dismissing:
            return []
        }
    }

    private mutating func finishDismiss() -> [AccessoryOverlayEffect] {
        guard case .dismissing = phase else { return [] }
        let pending = latched
        phase = gate.admits ? .armed : .closed
        guard gate.admits, let pending, suppressedID != pending.id else { return [] }
        let content = AccessoryOverlayContent.make(pending, gate: gate)
        if gate.reduceMotion {
            phase = .visible(content)
            return [.showNow]
        }
        phase = .appearing(content)
        return [.animateIn(gate.duration)]
    }
}

public struct AccessoryPreviewTile: Equatable, Sendable {
    public var visible: Bool
    public var title: String
    public var lines: [String]
    public var accessibilityLabel: String
    public var duration: Double
    public var emptyMessage: String
    public var showsListeningMode: Bool

    public init(visible: Bool, title: String, lines: [String], accessibilityLabel: String, duration: Double, emptyMessage: String, showsListeningMode: Bool) {
        self.visible = visible
        self.title = title
        self.lines = lines
        self.accessibilityLabel = accessibilityLabel
        self.duration = duration
        self.emptyMessage = emptyMessage
        self.showsListeningMode = showsListeningMode
    }

    public static func make(preferences: AccessoryPreferences, live: AccessoryConnectInput?, reduceMotion: Bool) -> AccessoryPreviewTile {
        let duration = reduceMotion ? 0 : MotionTokens.crossfadeDuration
        let gate = AccessoryOverlayGate(
            connectEnabled: preferences.earbudsOverlay,
            style: preferences.overlayStyle,
            reduceMotion: reduceMotion
        )
        guard gate.admits else {
            return AccessoryPreviewTile(
                visible: false,
                title: "Preview",
                lines: [],
                accessibilityLabel: AccessoryCopy.previewOff,
                duration: duration,
                emptyMessage: AccessoryCopy.previewOff,
                showsListeningMode: false
            )
        }
        let input = live?.sanitized ?? AccessoryConnectInput.preview
        let content = AccessoryOverlayContent.make(input, gate: gate)
        return AccessoryPreviewTile(
            visible: true,
            title: content.title,
            lines: content.lines,
            accessibilityLabel: content.accessibilityLabel,
            duration: duration,
            emptyMessage: "",
            showsListeningMode: content.showsListeningMode
        )
    }
}
