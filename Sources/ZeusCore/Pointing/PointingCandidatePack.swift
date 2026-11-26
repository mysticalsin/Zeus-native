import Foundation

/// The controls under the pointer for one pointing question, on one display.
/// Screenshot bytes stay out unless the person already turned that consent on.
/// A secure control keeps its role and rectangle, and keeps no label and no value.
/// Each acceptance answer is read from `PointingCandidatePackBox`. A zero-width space stays in a role.
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
    /// The limits, the role trim, and the stored image are read from `PointingCandidatePackBox`.
    public init?(displayID: UInt32, sendScreenshot: Bool = false, image: Data? = nil, candidates drafts: [Draft]) {
        guard let built = PointingCandidatePackBox.assemble(
            displayID: displayID,
            sendScreenshot: sendScreenshot,
            image: image,
            drafts: drafts
        ) else { return nil }
        self.displayID = built.displayID
        self.sendScreenshot = built.sendScreenshot
        self.image = built.image
        self.candidates = built.candidates
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

    static func cut(_ text: String, bytes limit: Int) -> String {
        PointingCandidatePackBox.cut(text, bytes: limit)
    }
}
