import CoreGraphics
import Foundation

/// Pure display-picker rules for Recordly: which display is selected without a click, how displays are
/// labelled, and how they are drawn as a to-scale arrangement. No AppKit, no permission, no I/O.
public enum RecordlyDisplayChoice {
    public typealias Display = RecordlySourceSelection.CatalogSnapshot.Display

    public enum Source: Equatable, Sendable {
        /// The display the owner already chose in this session and that is still connected.
        case current
        /// The display the owner chose last time, found again by its stable identity.
        case remembered
        /// The display with the menu bar.
        case main
        case firstAvailable
        case none
    }

    public struct Decision: Equatable, Sendable {
        public let selected: UInt32?
        public let source: Source
        /// The current choice was set but is no longer connected.
        public let lostCurrent: Bool
    }

    /// Order: the owner's current choice, then the remembered display, then the main display, then the first one.
    public static func decide(displays: [Display], current: UInt32?, remembered: String?) -> Decision {
        let usable = displays.filter { $0.id != 0 }
        let lost = current.map { id in !usable.contains { $0.id == id } } ?? false
        if let current, usable.contains(where: { $0.id == current }) {
            return Decision(selected: current, source: .current, lostCurrent: false)
        }
        if let remembered, !remembered.isEmpty,
           let match = usable.first(where: { $0.stableID == remembered }) {
            return Decision(selected: match.id, source: .remembered, lostCurrent: lost)
        }
        if let main = usable.first(where: \.isMain) {
            return Decision(selected: main.id, source: .main, lostCurrent: lost)
        }
        if let first = usable.first {
            return Decision(selected: first.id, source: .firstAvailable, lostCurrent: lost)
        }
        return Decision(selected: nil, source: .none, lostCurrent: lost)
    }

    // MARK: Labels

    /// "Built-in Retina Display", or "Display 2" when the system gave no name.
    public static func title(_ display: Display, position: Int) -> String {
        let trimmed = display.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Display \(position + 1)" : trimmed
    }

    /// "1512 x 982" using the multiplication sign.
    public static func size(_ display: Display) -> String {
        "\(Int(display.frame.width.rounded())) \u{00D7} \(Int(display.frame.height.rounded()))"
    }

    /// The compact single-display row: "Built-in Retina Display, Main".
    public static func compactLine(_ display: Display, position: Int) -> String {
        display.isMain ? "\(title(display, position: position)), Main" : title(display, position: position)
    }

    /// What VoiceOver reads for one display.
    public static func spokenLabel(_ display: Display, position: Int) -> String {
        let base = "\(title(display, position: position)), \(size(display))"
        return display.isMain ? "\(base), main display" : base
    }

    // MARK: Arrangement

    public struct Tile: Equatable, Sendable {
        public let id: UInt32
        public let rect: CGRect
    }

    /// Rectangles proportional to the displays' frames, placed as in System Settings (Displays), centred in
    /// `bounds`. Frames use the top-left origin, so the result can be drawn as is. Each tile is inset by `gap / 2`
    /// so touching displays stay distinguishable.
    public static func arrangement(_ displays: [Display], in bounds: CGSize, gap: CGFloat = 3) -> [Tile] {
        let usable = displays.filter {
            $0.id != 0 && $0.frame.width > 0 && $0.frame.height > 0
                && $0.frame.origin.x.isFinite && $0.frame.origin.y.isFinite
                && $0.frame.width.isFinite && $0.frame.height.isFinite
        }
        guard let first = usable.first, bounds.width > 0, bounds.height > 0 else { return [] }
        let union = usable.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let scale = min(bounds.width / union.width, bounds.height / union.height)
        let offsetX = (bounds.width - union.width * scale) / 2
        let offsetY = (bounds.height - union.height * scale) / 2
        return usable.map { display in
            let rect = CGRect(
                x: offsetX + (display.frame.minX - union.minX) * scale,
                y: offsetY + (display.frame.minY - union.minY) * scale,
                width: display.frame.width * scale,
                height: display.frame.height * scale
            )
            let inset = min(gap / 2, rect.width / 4, rect.height / 4)
            return Tile(id: display.id, rect: rect.insetBy(dx: inset, dy: inset))
        }
    }
}
