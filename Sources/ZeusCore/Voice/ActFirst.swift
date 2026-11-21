import Foundation

/// Whether a turn should act before it speaks a preamble.
public enum ActFirst {
    public static func suppressesFiller(_ transcript: String) -> Bool { false }
}
