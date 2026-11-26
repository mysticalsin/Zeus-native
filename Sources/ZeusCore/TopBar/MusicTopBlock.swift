import Foundation

/// The one value for the Music page's top block. The track and the lyrics cannot
/// both show: a press of the block that is already shown returns to the track,
/// and a press of any other block shows that block.
public enum MusicTopBlock: Equatable, Hashable, Sendable, CaseIterable {
    case track
    case lyrics

    /// `block` is the block the person pressed. The shown block returns to the
    /// track. Any other block becomes the one that is shown.
    public func pressed(_ block: MusicTopBlock) -> MusicTopBlock {
        block == self ? .track : block
    }
}
