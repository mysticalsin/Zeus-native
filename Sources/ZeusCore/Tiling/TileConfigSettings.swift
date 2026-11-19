import Foundation

extension TileConfig {
    /// The config the owner's settings describe. The split percentage the page shows becomes the engine's
    /// ratio (50 becomes 0.5), a pause is never stored so it starts false, and `TileConfig` clamps every number
    /// again, so a hand-edited value cannot make a layout the rules forbid. Nothing is floating at the start.
    public static func fromSettings(defaults: UserDefaults = .standard) -> TileConfig {
        TileConfig(enabled: FeatureSettings.tilingEnabled(defaults: defaults),
                   innerGap: FeatureSettings.tilingInnerGap(defaults: defaults),
                   outerGap: FeatureSettings.tilingOuterGap(defaults: defaults),
                   defaultRatio: FeatureSettings.tilingDefaultRatio(defaults: defaults),
                   base: FeatureSettings.tilingKeyBase(defaults: defaults),
                   excludedBundleIDs: FeatureSettings.tilingExcludedApps(defaults: defaults))
    }
}
