import Foundation

/// One output the Music page can offer. Pure facts: the app reads Core Audio and hands the
/// answers here. No device is opened and nothing is written.
public struct OutputDeviceFacts: Equatable, Sendable {
    public var objectID: UInt32
    /// Stable device identifier. Empty when the read failed.
    public var uid: String
    /// Name as Core Audio returned it, before cleaning.
    public var name: String
    /// Transport type code. Nil when the read failed. `0` is read and means nothing.
    public var transportCode: UInt32?
    /// Output-scope channel count. Nil when the read failed.
    public var outputChannels: Int?
    /// Output-scope "can be the default". Nil when the read failed.
    public var canBeDefault: Bool?
    /// Nil when the read failed.
    public var isHidden: Bool?
    /// Nil when the read failed.
    public var isAlive: Bool?

    public init(
        objectID: UInt32, uid: String, name: String, transportCode: UInt32?, outputChannels: Int?,
        canBeDefault: Bool?, isHidden: Bool?, isAlive: Bool?
    ) {
        self.objectID = objectID
        self.uid = uid
        self.name = name
        self.transportCode = transportCode
        self.outputChannels = outputChannels
        self.canBeDefault = canBeDefault
        self.isHidden = isHidden
        self.isAlive = isAlive
    }
}

/// How the sound leaves the Mac. An unknown code is `other`, never a guess at a real jack.
public enum OutputTransport: Equatable, Sendable {
    case builtIn
    case wired
    case bluetooth
    case wirelessSpeaker
    case display
    case virtual
    case other

    /// Four-character code, big endian, the same width Core Audio uses. A string that is not four
    /// bytes becomes `0`, which `init(code:)` reads as `other`.
    public static func fourCC(_ text: String) -> UInt32 {
        let bytes = Array(text.utf8)
        guard bytes.count == 4 else { return 0 }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// Nil, zero, and every code that is not one of the known transports.
    public init(code: UInt32?) {
        guard let code, code != 0 else {
            self = .other
            return
        }
        switch code {
        case Self.fourCC("bltn"): self = .builtIn
        case Self.fourCC("usb "), Self.fourCC("thun"), Self.fourCC("1394"), Self.fourCC("pci "), Self.fourCC("eavb"):
            self = .wired
        case Self.fourCC("blue"), Self.fourCC("blea"): self = .bluetooth
        case Self.fourCC("airp"): self = .wirelessSpeaker
        case Self.fourCC("hdmi"), Self.fourCC("dprt"): self = .display
        case Self.fourCC("virt"), Self.fourCC("grup"): self = .virtual
        default: self = .other
        }
    }

    /// The word a row and VoiceOver share. No dash other than the hyphen in "Built-in".
    public var word: String {
        switch self {
        case .builtIn: "Built-in"
        case .wired: "Wired"
        case .bluetooth: "Bluetooth"
        case .wirelessSpeaker: "Wireless speaker"
        case .display: "Display"
        case .virtual: "Virtual"
        case .other: "Other"
        }
    }

    var rank: Int {
        switch self {
        case .builtIn: 0
        case .wired: 1
        case .display: 2
        case .bluetooth: 3
        case .wirelessSpeaker: 4
        case .virtual: 5
        case .other: 6
        }
    }
}

/// Symbol names the list draws. The app substitutes `fallback` when the system has no image.
public enum OutputSymbol {
    public static let fallback = "speaker.wave.2"
    public static let all: Set<String> = [
        "speaker.wave.2", "cable.connector", "headphones", "airpodsmax", "airpodspro", "airpods",
        "beats.headphones", "airplayaudio", "display", "square.on.square.dashed", "hifispeaker",
    ]

    /// Bluetooth is the only transport whose name can change the symbol. Longest needle first.
    public static func name(transport: OutputTransport, name: String) -> String {
        switch transport {
        case .builtIn: return "speaker.wave.2"
        case .wired: return "cable.connector"
        case .bluetooth:
            let art = [("AirPods Max", "airpodsmax"), ("AirPods Pro", "airpodspro"), ("AirPods", "airpods"), ("Beats", "beats.headphones")]
            for (needle, symbol) in art where name.range(of: needle, options: .caseInsensitive) != nil {
                return symbol
            }
            return "headphones"
        case .wirelessSpeaker: return "airplayaudio"
        case .display: return "display"
        case .virtual: return "square.on.square.dashed"
        case .other: return "hifispeaker"
        }
    }
}

/// A device name safe to draw. Control and format scalars go away, the emoji joiner stays, and
/// whitespace folds to single spaces. Empty after that is absent.
public enum OutputName {
    public static let limit = 48

    public static func clean(_ raw: String) -> String? {
        var scalars: [Unicode.Scalar] = []
        var lastWasSpace = true
        for scalar in raw.unicodeScalars {
            if scalar == "\u{200D}" || scalar == "\u{FE0E}" || scalar == "\u{FE0F}" {
                scalars.append(scalar)
                lastWasSpace = false
                continue
            }
            if scalar.properties.isWhitespace {
                if !lastWasSpace {
                    scalars.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate:
                continue
            default:
                scalars.append(scalar)
                lastWasSpace = false
            }
        }
        while scalars.last == " " { scalars.removeLast() }
        let text = String(String.UnicodeScalarView(scalars))
        let cut = String(text.prefix(limit))
        guard cut.contains(where: { !$0.unicodeScalars.allSatisfy(isKeptMark) }) else { return nil }
        return cut
    }

    private static func isKeptMark(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200D}" || scalar == "\u{FE0E}" || scalar == "\u{FE0F}"
    }
}

/// One row. Identity is the UID. `isCurrent` does not change the order.
public struct OutputRoute: Equatable, Identifiable, Sendable {
    public var id: String { uid }
    public var uid: String
    public var objectID: UInt32
    public var name: String
    public var transport: OutputTransport
    public var symbol: String
    public var isCurrent: Bool

    public init(uid: String, objectID: UInt32, name: String, transport: OutputTransport, symbol: String, isCurrent: Bool) {
        self.uid = uid
        self.objectID = objectID
        self.name = name
        self.transport = transport
        self.symbol = symbol
        self.isCurrent = isCurrent
    }
}

/// Which devices are offered, in what order, and what they say.
public enum OutputRouteRules {
    /// At most this many rows. The live default is kept even when it would sit past the cut.
    public static let cap = 32
    private static let nameOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .numeric]

    public static func routes(from facts: [OutputDeviceFacts], defaultObjectID: UInt32?, locale: Locale) -> [OutputRoute] {
        let built = facts.compactMap { route(from: $0, defaultObjectID: defaultObjectID) }
        let sorted = built.sorted { comesBefore($0, $1, locale: locale) }
        return capped(sorted, locale: locale)
    }

    /// "Bluetooth, current". A status of only named blanks is the transport word alone.
    /// A zero-width space stays. The blank check is read from `OutputRoutesBox`.
    public static func spokenValue(for route: OutputRoute, status: String) -> String {
        let tail = OutputRoutesBox.trimmedStatus(status)
        if tail.isEmpty { return route.transport.word }
        return "\(route.transport.word), \(tail)"
    }

    private static func route(from fact: OutputDeviceFacts, defaultObjectID: UInt32?) -> OutputRoute? {
        guard !fact.uid.isEmpty, let name = OutputName.clean(fact.name) else { return nil }
        let isCurrent = defaultObjectID == fact.objectID
        let own = ZeusAudioDevices.isOwnAggregate(uid: fact.uid, name: fact.name)
            || ZeusAudioDevices.isOwnAggregate(uid: fact.uid, name: name)
        if !isCurrent {
            if own { return nil }
            if let channels = fact.outputChannels, channels <= 0 { return nil }
            if fact.canBeDefault == false || fact.isHidden == true || fact.isAlive == false { return nil }
        }
        let transport = OutputTransport(code: fact.transportCode)
        return OutputRoute(
            uid: fact.uid, objectID: fact.objectID, name: name, transport: transport,
            symbol: OutputSymbol.name(transport: transport, name: name), isCurrent: isCurrent
        )
    }

    private static func comesBefore(_ lhs: OutputRoute, _ rhs: OutputRoute, locale: Locale) -> Bool {
        if lhs.transport.rank != rhs.transport.rank { return lhs.transport.rank < rhs.transport.rank }
        let byName = lhs.name.compare(rhs.name, options: nameOptions, locale: locale)
        if byName != .orderedSame { return byName == .orderedAscending }
        let byUID = lhs.uid.compare(rhs.uid, options: nameOptions, locale: locale)
        if byUID != .orderedSame { return byUID == .orderedAscending }
        return lhs.objectID < rhs.objectID
    }

    private static func capped(_ sorted: [OutputRoute], locale: Locale) -> [OutputRoute] {
        guard sorted.count > cap else { return sorted }
        let head = Array(sorted.prefix(cap))
        guard let current = sorted.first(where: \.isCurrent), !head.contains(where: { $0.uid == current.uid }) else {
            return head
        }
        var kept = Array(sorted.prefix(cap - 1))
        kept.append(current)
        return kept.sorted { comesBefore($0, $1, locale: locale) }
    }
}
