import Foundation

/// The target box may paint before speech. The narration flight is a separate admission
/// and stays at or after first audio, so the pointing receipt's sync check still holds.
public enum PointerBoxLead {
    public struct Mark: Equatable, Sendable {
        public var id: String
        public var isRing: Bool
        public var inCaptureSpace: Bool
        public var captureID: UUID?

        public init(id: String, isRing: Bool, inCaptureSpace: Bool, captureID: UUID?) {
            self.id = id
            self.isRing = isRing
            self.inCaptureSpace = inCaptureSpace
            self.captureID = captureID
        }
    }

    /// Rings already placed in this capture, sorted by id. A label, an arrow, a canvas
    /// mark, or a ring from another capture is not the box.
    public static func boxIDs(_ marks: [Mark], captureID: UUID) -> [String] {
        marks.compactMap { mark in
            guard mark.isRing, mark.inCaptureSpace, mark.captureID == captureID else { return nil }
            return mark.id
        }.sorted()
    }
}
