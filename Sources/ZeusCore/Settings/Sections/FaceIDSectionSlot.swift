import Foundation

public enum FaceIDSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(id: "glass.faceID", title: "Face ID", filled: false, keys: [], order: 180)
    /// Drawn on the existing Privacy page. The sidebar slot stays empty.
    public static let placement = FaceVerificationPlacement.standard
}
