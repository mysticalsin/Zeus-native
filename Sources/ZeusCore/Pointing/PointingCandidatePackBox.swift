import Foundation

/// Which controls a pointing question may keep, and how a role is trimmed.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum PointingCandidatePackBox {
    public struct Assembly: Equatable, Sendable {
        public var displayID: UInt32
        public var sendScreenshot: Bool
        public var image: Data?
        public var candidates: [PointingCandidatePack.Candidate]
    }

    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a role is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}",
        "\u{0020}",
        "\u{0085}",
        "\u{00A0}",
        "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
        "\u{2028}", "\u{2029}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, blankScalars.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start {
            let previous = scalars.index(before: end)
            if blankScalars.contains(scalars[previous]) {
                end = previous
            } else {
                break
            }
        }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// The role a control may keep. Named blanks at the edges are removed. A zero-width space stays.
    /// A body of only named blanks is empty, and the pack refuses that control.
    public static func role(_ raw: String) -> String {
        cut(trimmed(raw), bytes: PointingCandidatePack.maxRoleBytes)
    }

    public static func cut(_ text: String, bytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var result = ""
        for character in text {
            let next = result + String(character)
            if next.utf8.count > limit { break }
            result = next
        }
        return result
    }

    /// One display, a handful of controls, and no screenshot unless consent is on.
    /// A secure control keeps its role and rectangle, and keeps no label and no value.
    public static func assemble(
        displayID: UInt32,
        sendScreenshot: Bool = false,
        image: Data? = nil,
        drafts: [PointingCandidatePack.Draft]
    ) -> Assembly? {
        guard displayID != 0 else { return nil }
        guard drafts.count <= PointingCandidatePack.maxCandidates else { return nil }
        let pixels = image?.isEmpty == false ? image : nil
        if let pixels, pixels.count > PointingCandidatePack.maxImageBytes { return nil }
        if !sendScreenshot, pixels != nil { return nil }
        var seen = Set<String>()
        var accepted: [PointingCandidatePack.Candidate] = []
        accepted.reserveCapacity(drafts.count)
        for draft in drafts {
            guard let candidate = candidate(from: draft) else { return nil }
            guard seen.insert(candidate.id).inserted else { return nil }
            accepted.append(candidate)
        }
        return Assembly(
            displayID: displayID,
            sendScreenshot: sendScreenshot,
            image: sendScreenshot ? pixels : nil,
            candidates: accepted
        )
    }

    private static func candidate(from draft: PointingCandidatePack.Draft) -> PointingCandidatePack.Candidate? {
        guard draft.id.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil else { return nil }
        let role = role(draft.role)
        guard !role.isEmpty else { return nil }
        guard draft.rect.isDrawable else { return nil }
        let label = draft.isSecure ? nil : draft.label.map { cut($0, bytes: PointingCandidatePack.maxLabelBytes) }
        return PointingCandidatePack.Candidate(
            id: draft.id,
            role: role,
            label: label,
            rect: draft.rect,
            isSecure: draft.isSecure
        )
    }
}
