import Foundation

/// What the engine reads from settings. Every number is clamped on the way in, so no stored value can
/// produce a layout the rules do not allow.
public struct TileConfig: Equatable, Sendable {
    public static let gapRange = 0.0...64.0
    public static let depthRange = 1...4
    public static let minTileSizeRange = 120.0...600.0
    public static let defaultGap = 8.0
    public static let defaultDepth = 3
    public static let defaultMinTileSize = 200.0

    /// Arranging windows is on. Off until the owner turns it on.
    public var enabled: Bool
    /// Arranging is stopped for now; windows stay where they are.
    public var paused: Bool
    public private(set) var innerGap: Double
    public private(set) var outerGap: Double
    /// Splits allowed between the root and any window: 3 gives up to 8 tiles.
    public private(set) var maxDepth: Int
    /// The least width and height a new tile may have.
    public private(set) var minTileSize: Double
    /// The share of a new split that goes to the existing window.
    public private(set) var defaultRatio: Double
    public var base: TileModifierBase
    /// Windows left out of the layout for now.
    public var floating: Set<TileWindowID>
    public var excludedBundleIDs: Set<String>

    /// Gaps clamp to 0 ... 64, depth to 1 ... 4, minimum tile size to 120 ... 600 and the ratio to
    /// `TileRatio`'s bounds. A number that is not a number falls back to its default.
    public init(enabled: Bool = false, paused: Bool = false,
                innerGap: Double = TileConfig.defaultGap, outerGap: Double = TileConfig.defaultGap,
                maxDepth: Int = TileConfig.defaultDepth, minTileSize: Double = TileConfig.defaultMinTileSize,
                defaultRatio: Double = TileRatio.standard, base: TileModifierBase = .controlOption,
                floating: Set<TileWindowID> = [], excludedBundleIDs: Set<String> = []) {
        self.enabled = enabled
        self.paused = paused
        self.innerGap = Self.clamp(innerGap, Self.gapRange, fallback: Self.defaultGap)
        self.outerGap = Self.clamp(outerGap, Self.gapRange, fallback: Self.defaultGap)
        self.maxDepth = min(max(maxDepth, Self.depthRange.lowerBound), Self.depthRange.upperBound)
        self.minTileSize = Self.clamp(minTileSize, Self.minTileSizeRange, fallback: Self.defaultMinTileSize)
        self.defaultRatio = TileRatio.clamp(defaultRatio)
        self.base = base
        self.floating = floating
        self.excludedBundleIDs = excludedBundleIDs
    }

    /// The shipped defaults.
    public static let defaults = TileConfig()

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        if value.isNaN { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
