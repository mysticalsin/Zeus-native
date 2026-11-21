import Foundation

/// How a provider clip is handed to the player.
public enum ProviderStreamPlayback {
    /// Plays one joined buffer after every chunk has arrived.
    public static func deliver(_ chunks: [Data], play: (Data) -> Void) -> Data {
        let all = chunks.reduce(into: Data()) { $0.append($1) }
        if !all.isEmpty { play(all) }
        return all
    }
}
