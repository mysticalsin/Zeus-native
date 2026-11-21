import Foundation

/// How a provider clip is handed to the player.
public enum ProviderStreamPlayback {
    /// Hands each chunk to the player as it arrives, and still returns the joined bytes.
    public static func deliver(_ chunks: [Data], play: (Data) -> Void) -> Data {
        var all = Data()
        for chunk in chunks where !chunk.isEmpty {
            play(chunk)
            all.append(chunk)
        }
        return all
    }
}
