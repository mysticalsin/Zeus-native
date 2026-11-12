import Foundation

/// Which call app a window reading came from.
public enum MeetingAppKind: String, Codable, Sendable, CaseIterable {
    case zoom, teams, meet, slack, other
}

/// One participant tile as the call window shows it right now.
public struct MeetingParticipantState: Equatable, Sendable {
    public var name: String
    public var isSpeaking: Bool
    public var isMuted: Bool
    /// The tile is the person at the keyboard ("(You)", "(Vous)"). Their voice is the microphone channel.
    public var isSelf: Bool

    public init(name: String, isSpeaking: Bool = false, isMuted: Bool = false, isSelf: Bool = false) {
        self.name = name
        self.isSpeaking = isSpeaking
        self.isMuted = isMuted
        self.isSelf = isSelf
    }
}

/// Turns the text a call window exposes for a participant tile ("Marie Dubois (Guest) is speaking",
/// "Paul, muted", "Chloé (Invitée), micro coupé", "Sam, active speaker") into a clean name plus state.
/// English and French. Pure: the Accessibility reader only collects strings and hands them here.
public enum MeetingSpeakerLabelParser {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals in this file; a bad one is a programming error caught by the tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let speakingPatterns: [NSRegularExpression] = [
        regex(#"\s+is\s+speaking\b"#),
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\bactive\s+speaker\b"#),
        regex(#"\s+est\s+en\s+train\s+de\s+parler\b"#),
        regex(#"\s+en\s+train\s+de\s+parler\b"#),
        regex(#"\s+parle\b"#),
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\bintervenant\s+actif\b"#),
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\borateur\s+actif\b"#),
    ]

    private static let mutedPatterns: [NSRegularExpression] = [
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\bmuted\b"#),
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\bmicro(?:phone)?\s+coup[ée]\b"#),
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\bmicro\s+d[ée]sactiv[ée]\b"#),
        regex(#"[,;:\-\x{2013}\x{2014}]?\s*\ben\s+sourdine\b"#),
    ]

    private static let selfSuffix = regex(#"\((?:you|vous|moi|me)\)"#)
    private static let suffixes: [NSRegularExpression] = [
        regex(#"\s*\((?:guest|external|you|host|organizer|presenter|invit[ée]e?|externe|vous|moi|h[ôo]te|organisateur|organisatrice|pr[ée]sentateur|pr[ée]sentatrice)\)"#),
    ]

    /// Words that are call-window controls or headings, never a person.
    private static let notNames: Set<String> = [
        "participants", "participant", "people", "chat", "mute", "unmute", "video", "share", "share screen", "leave",
        "end", "end call", "more", "reactions", "raise hand", "lower hand", "record", "recording", "settings", "view",
        "gallery view", "speaker view", "meeting", "call", "huddle", "invite", "apps", "whiteboard", "captions",
        "discussion", "partager", "partager l'ecran", "quitter", "lever la main", "baisser la main", "reunion",
        "appel", "inviter", "sous-titres", "plus", "reactions", "microphone", "camera", "present", "present now",
        "you", "vous", "me", "moi", "unknown", "guest", "invite", "external", "externe",
    ]

    public struct Tile: Equatable, Sendable {
        public let name: String
        public let isSpeaking: Bool
        public let isMuted: Bool
        public let isSelf: Bool

        public var state: MeetingParticipantState {
            MeetingParticipantState(name: name, isSpeaking: isSpeaking && !isMuted, isMuted: isMuted, isSelf: isSelf)
        }
    }

    public static func isSpeakingSignal(_ text: String) -> Bool { matches(speakingPatterns, in: text) }
    public static func isMutedSignal(_ text: String) -> Bool { matches(mutedPatterns, in: text) }

    /// The tile a label describes, or nil when what is left is empty or a window control, not a person.
    public static func parse(_ raw: String) -> Tile? {
        let speaking = isSpeakingSignal(raw)
        let muted = isMutedSignal(raw)
        let isSelf = matches([selfSuffix], in: raw)
        var text = raw
        for pattern in speakingPatterns + mutedPatterns { text = strip(pattern, from: text) }
        guard let name = clean(text) else { return nil }
        return Tile(name: name, isSpeaking: speaking, isMuted: muted, isSelf: isSelf)
    }

    /// A display name with the role suffixes and stray punctuation removed; nil when nothing person-like is left.
    public static func clean(_ raw: String) -> String? {
        var text = raw
        for pattern in suffixes { text = strip(pattern, from: text) }
        text = text.replacingOccurrences(of: "\u{200E}", with: "").replacingOccurrences(of: "\u{200F}", with: "")
        let edge = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-|()[]\u{2013}\u{2014}\u{2022}\u{00B7}"))
        text = text.trimmingCharacters(in: edge)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty, text.count <= 60, text.contains(where: \.isLetter) else { return nil }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !notNames.contains(folded) else { return nil }
        return text
    }

    /// Two reads of the same person agree on one key whatever the case, accents or spacing.
    public static func key(_ name: String) -> String { ScribeAttendeeNames.key(name) }

    private static func matches(_ patterns: [NSRegularExpression], in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    private static func strip(_ pattern: NSRegularExpression, from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
