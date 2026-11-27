import Foundation

/// Which Recordly display is selected, how it is named, and where its tile sits, as `Double`
/// edges. The caller supplies the list. This type does not read a screen, a pointer, or a clock.
public enum RecordlyDisplayChoiceBox {
    public struct Choice: Equatable, Sendable {
        public var id: UInt32
        public var stableID: String?
        public var isMain: Bool

        public init(id: UInt32, stableID: String? = nil, isMain: Bool = false) {
            self.id = id
            self.stableID = stableID
            self.isMain = isMain
        }
    }

    public enum Source: String, Equatable, Sendable {
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
        public var selected: UInt32?
        public var source: Source
        /// The current choice was set but is no longer connected.
        public var lostCurrent: Bool

        public init(selected: UInt32?, source: Source, lostCurrent: Bool) {
            self.selected = selected
            self.source = source
            self.lostCurrent = lostCurrent
        }
    }

    public struct Frame: Equatable, Sendable {
        public var id: UInt32
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(id: UInt32, x: Double, y: Double, width: Double, height: Double) {
            self.id = id
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct Rect: Equatable, Sendable {
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
    }

    public struct Tile: Equatable, Sendable {
        public var id: UInt32
        public var rect: Rect

        public init(id: UInt32, rect: Rect) {
            self.id = id
            self.rect = rect
        }
    }

    /// Order: the owner's current choice, then the remembered display, then the main display,
    /// then the first one. An id of zero is never a display.
    public static func decide(displays: [Choice], current: UInt32?, remembered: String?) -> Decision {
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

    /// The trimmed name, or "Display N" when the system gave none. `position` is zero-based.
    public static func title(name: String?, position: Int) -> String {
        let trimmed = RecordlyDisplayNameBox.trimmedName(name ?? "")
        return trimmed.isEmpty ? "Display \(position + 1)" : trimmed
    }

    /// "1512 x 982" using the multiplication sign. Halves round away from zero.
    public static func size(width: Double, height: Double) -> String {
        "\(Int(width.rounded())) \u{00D7} \(Int(height.rounded()))"
    }

    /// The compact single-display row: "Built-in Retina Display, Main".
    public static func compactLine(name: String?, position: Int, isMain: Bool) -> String {
        let label = title(name: name, position: position)
        return isMain ? "\(label), Main" : label
    }

    /// What VoiceOver reads for one display.
    public static func spokenLabel(name: String?, position: Int, width: Double, height: Double, isMain: Bool) -> String {
        let base = "\(title(name: name, position: position)), \(size(width: width, height: height))"
        return isMain ? "\(base), main display" : base
    }

    /// Rectangles proportional to the frames, centred in the bounds. Frames use a top-left origin.
    /// Each tile is inset by `gap / 2`, and never by more than a quarter of the tile.
    public static func arrangement(displays: [Frame], boundsWidth: Double, boundsHeight: Double, gap: Double = 3) -> [Tile] {
        let usable = displays.filter { frame in
            frame.id != 0 && frame.width > 0 && frame.height > 0
                && frame.x.isFinite && frame.y.isFinite
                && frame.width.isFinite && frame.height.isFinite
        }
        guard let first = usable.first, boundsWidth > 0, boundsHeight > 0 else { return [] }
        let combined = usable.dropFirst().reduce(rect(first)) { united($0, rect($1)) }
        let scale = min(boundsWidth / combined.width, boundsHeight / combined.height)
        let offsetX = (boundsWidth - combined.width * scale) / 2
        let offsetY = (boundsHeight - combined.height * scale) / 2
        return usable.map { display in
            let placed = Rect(
                x: offsetX + (display.x - combined.x) * scale,
                y: offsetY + (display.y - combined.y) * scale,
                width: display.width * scale,
                height: display.height * scale)
            let inset = min(gap / 2, placed.width / 4, placed.height / 4)
            return Tile(id: display.id, rect: insetBy(placed, dx: inset, dy: inset))
        }
    }

    private static func rect(_ frame: Frame) -> Rect {
        Rect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private static func united(_ lhs: Rect, _ rhs: Rect) -> Rect {
        let minX = min(lhs.x, rhs.x)
        let minY = min(lhs.y, rhs.y)
        let maxX = max(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = max(lhs.y + lhs.height, rhs.y + rhs.height)
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func insetBy(_ rect: Rect, dx: Double, dy: Double) -> Rect {
        Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width - dx * 2, height: rect.height - dy * 2)
    }
}
