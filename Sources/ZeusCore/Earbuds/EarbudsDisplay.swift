import Foundation

/// Words a person reads for earbuds. Pure values: no device is opened and nothing is written.
/// A hidden name is the word "Earbuds". Otherwise control and format scalars are dropped, a run of
/// zero-width joiners is dropped, one joiner between other scalars stays, and line, paragraph and
/// space separators fold to one U+0020. Private-use and unassigned scalars are dropped. The result
/// is trimmed, and past 32 characters the last one is an ellipsis. Nothing left is "Earbuds".
/// `EarbudsPart` is the battery list in `EarbudsBattery`. This file reads that one declaration.

public enum EarbudsLevel: Equatable, Sendable {
    case unknown
    case fresh(Int)
    case lastKnown(Int)
}

public struct EarbudsPartReading: Equatable, Sendable {
    public var part: EarbudsPart
    public var level: EarbudsLevel

    public init(part: EarbudsPart, level: EarbudsLevel) {
        self.part = part
        self.level = level
    }
}

/// Facts the words need. This is not the presence cue.
public struct EarbudsCueFacts: Equatable, Sendable {
    public var name: String
    public var connected: Bool
    public var parts: [EarbudsPartReading]

    public init(name: String, connected: Bool, parts: [EarbudsPartReading] = []) {
        self.name = name
        self.connected = connected
        self.parts = parts
    }
}

public enum EarbudsMode: Equatable, Hashable, Sendable {
    case off
    case noiseCancelling
    case transparency
    case adaptive
}

public struct EarbudsModeChoice: Equatable, Sendable {
    public var mode: EarbudsMode
    public var available: Bool

    public init(mode: EarbudsMode, available: Bool) {
        self.mode = mode
        self.available = available
    }
}

public struct EarbudsModeStatus: Equatable, Sendable {
    public var current: EarbudsMode
    public var choices: [EarbudsModeChoice]
    public var pending: EarbudsMode?

    public init(current: EarbudsMode, choices: [EarbudsModeChoice], pending: EarbudsMode? = nil) {
        self.current = current
        self.choices = choices
        self.pending = pending
    }
}

public enum EarbudsModeOutcome: Equatable, Sendable {
    case changed(EarbudsMode)
    case stayed(EarbudsMode)
}

public enum EarbudsCapsuleKind: Equatable, Sendable {
    case available
    case refused
    case pending
    case selected
    case fixed
}

public struct EarbudsCapsule: Equatable, Sendable {
    public var title: String
    public var symbol: String
    public var spoken: String
    public var kind: EarbudsCapsuleKind

    public init(title: String, symbol: String, spoken: String, kind: EarbudsCapsuleKind) {
        self.title = title
        self.symbol = symbol
        self.spoken = spoken
        self.kind = kind
    }
}

public struct EarbudsCueLine: Equatable, Sendable {
    public var text: String
    public var symbol: String?

    public init(text: String, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }
}

public struct EarbudsPanelPart: Equatable, Sendable {
    public var text: String
    public var symbol: String?

    public init(text: String, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }
}

public enum EarbudsName {
    /// At most this many characters, counting the ellipsis when the name is cut.
    public static let limit = 32

    public static func display(_ raw: String, hideDetails: Bool) -> String {
        if hideDetails { return "Earbuds" }
        let text = cleaned(raw)
        return text.isEmpty ? "Earbuds" : text
    }

    static func cleaned(_ raw: String) -> String {
        var scalars: [Unicode.Scalar] = []
        var lastWasSpace = true
        for scalar in raw.unicodeScalars {
            if isKeptMark(scalar) {
                scalars.append(scalar)
                lastWasSpace = false
                continue
            }
            if foldsToSpace(scalar) {
                if !lastWasSpace {
                    scalars.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                continue
            default:
                scalars.append(scalar)
                lastWasSpace = false
            }
        }
        let text = string(collapseSpaces(dropJoinerRuns(scalars)))
        guard !text.isEmpty, !text.unicodeScalars.allSatisfy(isKeptMark) else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }

    private static func foldsToSpace(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    private static func isKeptMark(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200D}" || scalar == "\u{FE0E}" || scalar == "\u{FE0F}"
    }

    /// Two or more joiners in a row are not an emoji joiner. One joiner stays.
    private static func dropJoinerRuns(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\u{200D}" {
                var end = index + 1
                while end < scalars.count, scalars[end] == "\u{200D}" { end += 1 }
                if end - index == 1 { out.append(scalars[index]) }
                index = end
            } else {
                out.append(scalars[index])
                index += 1
            }
        }
        return out
    }

    private static func collapseSpaces(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var lastWasSpace = true
        for scalar in scalars {
            if scalar == " " {
                if !lastWasSpace {
                    out.append(scalar)
                    lastWasSpace = true
                }
                continue
            }
            out.append(scalar)
            lastWasSpace = false
        }
        while out.last == " " { out.removeLast() }
        return out
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var text = ""
        for scalar in scalars { text.unicodeScalars.append(scalar) }
        return text
    }
}

public enum EarbudsWords {
    public static func cueStatus(_ cue: EarbudsCueFacts) -> [EarbudsCueLine] {
        if !cue.connected { return [EarbudsCueLine(text: "Disconnected")] }
        let lines = ordered(cue.parts).compactMap(cueLine)
        return lines.isEmpty ? [EarbudsCueLine(text: "Connected")] : lines
    }

    public static func panelParts(_ parts: [EarbudsPartReading]) -> [EarbudsPanelPart] {
        ordered(parts).map(panelPart)
    }

    public static func spoken(_ cue: EarbudsCueFacts, hideDetails: Bool) -> String {
        let name = EarbudsName.display(cue.name, hideDetails: hideDetails)
        guard cue.connected else { return "\(name) disconnected." }
        let phrases = ordered(cue.parts).enumerated().map { spokenPhrase($1, first: $0 == 0) }
        guard !phrases.isEmpty else { return "\(name) connected." }
        return "\(name) connected. \(phrases.joined(separator: ", "))."
    }

    public static func modeTitle(_ mode: EarbudsMode) -> String {
        switch mode {
        case .off: "Off"
        case .noiseCancelling: "Noise cancelling"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        }
    }

    /// Generic marks. A vendor product symbol is not used. A Mac has not confirmed the images.
    public static func modeSymbol(_ mode: EarbudsMode) -> String {
        switch mode {
        case .off: "speaker.slash"
        case .noiseCancelling: "waveform.slash"
        case .transparency: "ear"
        case .adaptive: "waveform"
        }
    }

    public static func modeCapsules(_ status: EarbudsModeStatus) -> [EarbudsCapsule] {
        var capsules: [EarbudsCapsule] = []
        var seen: Set<EarbudsMode> = []
        for choice in status.choices where choice.mode != .adaptive {
            guard seen.insert(choice.mode).inserted else { continue }
            capsules.append(capsule(for: choice, status: status))
        }
        if !seen.contains(status.current) {
            capsules.append(fixed(status.current))
        }
        return capsules
    }

    public static func spoken(_ outcome: EarbudsModeOutcome) -> String {
        switch outcome {
        case .changed(let mode):
            "\(modeTitle(mode)) on."
        case .stayed(let mode):
            "Listening mode stayed on \(modeTitle(mode))."
        }
    }

    private static func cueLine(_ reading: EarbudsPartReading) -> EarbudsCueLine? {
        guard let number = EarbudsLevels.shown(reading.level) else { return nil }
        let text = cueLabel(reading.part).map { "\($0) \(number)%" } ?? "\(number)%"
        let symbol = EarbudsLevels.lastKnown(reading.level) ? "clock" : nil
        return EarbudsCueLine(text: text, symbol: symbol)
    }

    private static func panelPart(_ reading: EarbudsPartReading) -> EarbudsPanelPart {
        if let number = EarbudsLevels.shown(reading.level) {
            let text = panelLabel(reading.part).map { "\($0) \(number)%" } ?? "\(number)%"
            let symbol = EarbudsLevels.lastKnown(reading.level) ? "clock" : nil
            return EarbudsPanelPart(text: text, symbol: symbol)
        }
        let text = panelLabel(reading.part).map { "\($0) unknown" } ?? "unknown"
        return EarbudsPanelPart(text: text, symbol: "questionmark.circle")
    }

    private static func spokenPhrase(_ reading: EarbudsPartReading, first: Bool) -> String {
        let label = spokenLabel(reading.part, first: first)
        let phrase: String
        if let number = EarbudsLevels.shown(reading.level) {
            let body = label.map { "\($0) \(number) percent" } ?? "\(number) percent"
            phrase = EarbudsLevels.lastKnown(reading.level) ? "\(body) last known" : body
        } else {
            phrase = label.map { "\($0) unknown" } ?? "unknown"
        }
        guard first, let head = phrase.first, head.isLowercase else { return phrase }
        return head.uppercased() + phrase.dropFirst()
    }

    private static func capsule(for choice: EarbudsModeChoice, status: EarbudsModeStatus) -> EarbudsCapsule {
        let title = modeTitle(choice.mode)
        let kind: EarbudsCapsuleKind
        let symbol: String
        if choice.mode == status.current {
            kind = .selected
            symbol = modeSymbol(choice.mode)
        } else if status.pending == choice.mode {
            kind = .pending
            symbol = modeSymbol(choice.mode)
        } else if !choice.available {
            kind = .refused
            symbol = "exclamationmark.circle"
        } else {
            kind = .available
            symbol = modeSymbol(choice.mode)
        }
        return EarbudsCapsule(title: title, symbol: symbol, spoken: capsuleSpoken(title, kind), kind: kind)
    }

    private static func fixed(_ mode: EarbudsMode) -> EarbudsCapsule {
        let title = modeTitle(mode)
        return EarbudsCapsule(title: title, symbol: modeSymbol(mode), spoken: capsuleSpoken(title, .fixed), kind: .fixed)
    }

    private static func capsuleSpoken(_ title: String, _ kind: EarbudsCapsuleKind) -> String {
        switch kind {
        case .available: title
        case .selected, .fixed: "\(title), selected"
        case .refused: "\(title), not available"
        case .pending: "\(title), pending"
        }
    }

    private static func cueLabel(_ part: EarbudsPart) -> String? {
        switch part {
        case .left: "L"
        case .right: "R"
        case .case: "Case"
        case .single: nil
        }
    }

    private static func panelLabel(_ part: EarbudsPart) -> String? {
        switch part {
        case .left: "Left"
        case .right: "Right"
        case .case: "Case"
        case .single: nil
        }
    }

    private static func spokenLabel(_ part: EarbudsPart, first: Bool) -> String? {
        switch part {
        case .left: first ? "Left" : "left"
        case .right: first ? "Right" : "right"
        case .case: first ? "Case" : "case"
        case .single: nil
        }
    }

    private static func ordered(_ parts: [EarbudsPartReading]) -> [EarbudsPartReading] {
        parts.sorted { rank($0.part) < rank($1.part) }
    }

    private static func rank(_ part: EarbudsPart) -> Int {
        switch part {
        case .left: 0
        case .right: 1
        case .case: 2
        case .single: 3
        }
    }
}

public enum EarbudsMatch {
    /// True when the UID holds the address, separators and case ignored, or the cleaned names are equal.
    public static func same(id: String, name: String, outputUID: String, outputName: String) -> Bool {
        let address = hexDigits(id)
        if address.count >= 12, address.count.isMultiple(of: 2), hexDigits(outputUID).contains(address) {
            return true
        }
        let left = EarbudsName.cleaned(name)
        let right = EarbudsName.cleaned(outputName)
        return !left.isEmpty && left == right
    }

    private static func hexDigits(_ raw: String) -> String {
        var out = ""
        for byte in raw.utf8 {
            switch byte {
            case 48...57, 97...102:
                out.append(Character(Unicode.Scalar(byte)))
            case 65...70:
                out.append(Character(Unicode.Scalar(byte + 32)))
            default:
                continue
            }
        }
        return out
    }
}

public struct EarbudsShown: Equatable, Sendable {
    public var id: String
    public var name: String
    public var parts: [EarbudsPartReading]

    public init(id: String, name: String, parts: [EarbudsPartReading]) {
        self.id = id
        self.name = name
        self.parts = parts
    }
}

public struct EarbudsModeShown: Equatable, Sendable {
    public var outputUID: String
    public var outputName: String
    public var status: EarbudsModeStatus

    public init(outputUID: String, outputName: String, status: EarbudsModeStatus) {
        self.outputUID = outputUID
        self.outputName = outputName
        self.status = status
    }
}

/// One group. The name, the battery parts and the mode row live on this one value.
public struct EarbudsPanelGroup: Equatable, Sendable {
    public var name: String
    public var parts: [EarbudsPanelPart]
    public var capsules: [EarbudsCapsule]

    public init(name: String, parts: [EarbudsPanelPart], capsules: [EarbudsCapsule]) {
        self.name = name
        self.parts = parts
        self.capsules = capsules
    }
}

public enum EarbudsPanelModel {
    public static func make(presence: EarbudsShown?, mode: EarbudsModeShown?, hideDetails: Bool) -> EarbudsPanelGroup? {
        let nameSource: String
        let parts: [EarbudsPanelPart]
        let showMode: Bool
        if let presence {
            nameSource = presence.name
            parts = EarbudsWords.panelParts(presence.parts)
            if let mode {
                showMode = EarbudsMatch.same(
                    id: presence.id, name: presence.name, outputUID: mode.outputUID, outputName: mode.outputName
                )
            } else {
                showMode = false
            }
        } else if let mode {
            nameSource = mode.outputName
            parts = []
            showMode = true
        } else {
            return nil
        }
        let capsules = showMode ? mode.map { EarbudsWords.modeCapsules($0.status) } ?? [] : []
        if parts.isEmpty && capsules.isEmpty { return nil }
        return EarbudsPanelGroup(
            name: EarbudsName.display(nameSource, hideDetails: hideDetails),
            parts: parts,
            capsules: capsules
        )
    }
}

public enum EarbudsSettingsFace: Equatable, Sendable {
    case allowed
    case notAsked
    case notAllowed
    case batteryUnavailable
    case unavailable
}

public enum EarbudsSettingsWords {
    public static func state(_ status: EarbudsSettingsFace) -> String {
        switch status {
        case .allowed: "Allowed"
        case .notAsked: "Not asked"
        case .notAllowed: "Not allowed"
        case .batteryUnavailable: "Battery not available"
        case .unavailable: "Not available"
        }
    }
}

enum EarbudsLevels {
    static func shown(_ level: EarbudsLevel) -> Int? {
        switch level {
        case .unknown:
            return nil
        case .fresh(let number), .lastKnown(let number):
            return (1...100).contains(number) ? number : nil
        }
    }

    static func lastKnown(_ level: EarbudsLevel) -> Bool {
        if case .lastKnown(let number) = level, (1...100).contains(number) { return true }
        return false
    }
}
