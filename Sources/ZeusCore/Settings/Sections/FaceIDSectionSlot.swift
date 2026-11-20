import Foundation

public enum FaceIDSectionSlot: GlassSlotProviding {
    public static let descriptor = GlassSectionSlot(id: "glass.faceID", title: "Face ID", filled: false, keys: [], order: 180)
}
