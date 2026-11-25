import Foundation

/// Which drawing marks paint when the draw tag arrives, before that sentence's audio.
public enum DrawingPaintLead {
    /// The earliest sentence index. Later sentences stay pending until their audio starts.
    /// An empty draw has nothing due.
    public static func sentenceDueOnArrival<S: Sequence>(_ sentences: S) -> Int? where S.Element == Int {
        sentences.min()
    }
}
