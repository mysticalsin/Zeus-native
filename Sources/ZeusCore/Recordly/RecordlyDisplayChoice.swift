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
        let decision = RecordlyDisplayChoiceBox.decide(
            displays: displays.map { display in
                RecordlyDisplayChoiceBox.Choice(id: display.id, stableID: display.stableID, isMain: display.isMain)
            },
            current: current,
            remembered: remembered)
        return Decision(selected: decision.selected, source: source(decision.source), lostCurrent: decision.lostCurrent)
    }

    private static func source(_ source: RecordlyDisplayChoiceBox.Source) -> Source {
        switch source {
        case .current: .current
        case .remembered: .remembered
        case .main: .main
        case .firstAvailable: .firstAvailable
        case .none: .none
        }
    }

    // MARK: Labels

    /// "Built-in Retina Display", or "Display 2" when the system gave no name.
    public static func title(_ display: Display, position: Int) -> String {
        RecordlyDisplayChoiceBox.title(name: display.name, position: position)
    }

    /// "1512 x 982" using the multiplication sign.
    public static func size(_ display: Display) -> String {
        RecordlyDisplayChoiceBox.size(width: Double(display.frame.width), height: Double(display.frame.height))
    }

    /// The compact single-display row: "Built-in Retina Display, Main".
    public static func compactLine(_ display: Display, position: Int) -> String {
        RecordlyDisplayChoiceBox.compactLine(name: display.name, position: position, isMain: display.isMain)
    }

    /// What VoiceOver reads for one display.
    public static func spokenLabel(_ display: Display, position: Int) -> String {
        RecordlyDisplayChoiceBox.spokenLabel(
            name: display.name,
            position: position,
            width: Double(display.frame.width),
            height: Double(display.frame.height),
            isMain: display.isMain)
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
        let tiles = RecordlyDisplayChoiceBox.arrangement(
            displays: displays.map { display in
                RecordlyDisplayChoiceBox.Frame(
                    id: display.id,
                    x: Double(display.frame.minX),
                    y: Double(display.frame.minY),
                    width: Double(display.frame.width),
                    height: Double(display.frame.height))
            },
            boundsWidth: Double(bounds.width),
            boundsHeight: Double(bounds.height),
            gap: Double(gap))
        return tiles.map { tile in
            Tile(id: tile.id, rect: CGRect(x: tile.rect.x, y: tile.rect.y, width: tile.rect.width, height: tile.rect.height))
        }
    }
}
