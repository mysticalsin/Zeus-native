import Foundation

/// The controls under the pointer for one pointing question, on one display.
/// Screenshot bytes stay out unless the person already turned that consent on.
/// A secure control keeps its role and rectangle, and keeps no label and no value.
public struct PointingCandidatePack: Equatable, Sendable, Codable {
    public static let maxCandidates = 8
    public static let maxLabelBytes = 128
    public static let maxRoleBytes = 64
    /// The same ceiling the pointing plan uses for one snapshot.
    public static let maxImageBytes = 8 * 1024 * 1024

    public struct Rect: Equatable, Sendable, Codable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// A real rectangle. A negative origin is a display to the left of the primary.
        public var isDrawable: Bool {
            x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
        }
    }

    /// What the accessibility lookup found, before the pack applies its limits.
    public struct Draft: Equatable, Sendable {
        public var id: String
        public var role: String
        public var label: String?
        public var rect: Rect
        public var isSecure: Bool

        public init(id: String, role: String, label: String? = nil, rect: Rect, isSecure: Bool = false) {
            self.id = id
            self.role = role
            self.label = label
            self.rect = rect
            self.isSecure = isSecure
        }
    }

    public struct Candidate: Equatable, Sendable, Codable {
        public var id: String
        public var role: String
        /// Absent when the control is secure, and cut at 128 UTF-8 bytes otherwise.
        public var label: String?
        public var rect: Rect
        public var isSecure: Bool

        public init(id: String, role: String, label: String?, rect: Rect, isSecure: Bool) {
            self.id = id
            self.role = role
            self.label = label
            self.rect = rect
            self.isSecure = isSecure
        }
    }

    public var displayID: UInt32
    /// Off unless the person turned on sending a screenshot with the question.
    public var sendScreenshot: Bool
    /// Pixel bytes for that one display. Nil whenever `sendScreenshot` is off.
    public var image: Data?
    public var candidates: [Candidate]

    public var carriesImageBytes: Bool { !(image?.isEmpty ?? true) }

    /// One display, a handful of controls, and no screenshot unless consent is on.
    public init?(displayID: UInt32, sendScreenshot: Bool = false, image: Data? = nil, candidates drafts: [Draft]) {
        guard displayID != 0 else { return nil }
        guard drafts.count <= Self.maxCandidates else { return nil }
        let pixels = image?.isEmpty == false ? image : nil
        if let pixels, pixels.count > Self.maxImageBytes { return nil }
        if !sendScreenshot, pixels != nil { return nil }
        var seen = Set<String>()
        var accepted: [Candidate] = []
        accepted.reserveCapacity(drafts.count)
        for draft in drafts {
            guard let candidate = Self.candidate(from: draft) else { return nil }
            guard seen.insert(candidate.id).inserted else { return nil }
            accepted.append(candidate)
        }
        self.displayID = displayID
        self.sendScreenshot = sendScreenshot
        self.image = sendScreenshot ? pixels : nil
        self.candidates = accepted
    }

    private enum CodingKeys: String, CodingKey {
        case displayID, sendScreenshot, image, candidates
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(sendScreenshot, forKey: .sendScreenshot)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(candidates, forKey: .candidates)
    }

    private static func candidate(from draft: Draft) -> Candidate? {
        guard draft.id.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil else { return nil }
        let role = cut(draft.role.trimmingCharacters(in: .whitespacesAndNewlines), bytes: maxRoleBytes)
        guard !role.isEmpty else { return nil }
        guard draft.rect.isDrawable else { return nil }
        let label = draft.isSecure ? nil : draft.label.map { cut($0, bytes: maxLabelBytes) }
        return Candidate(id: draft.id, role: role, label: label, rect: draft.rect, isSecure: draft.isSecure)
    }

    static func cut(_ text: String, bytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var result = ""
        for character in text {
            let next = result + String(character)
            if next.utf8.count > limit { break }
            result = next
        }
        return result
    }
}
