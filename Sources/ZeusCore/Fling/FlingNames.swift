import Foundation

public enum FlingNameError: Error, Equatable, Sendable {
    /// Holds a separator, a control character, a leading dot, or is empty, `.` or `..`.
    case unsafe
    case tooLong
}

/// The file-name rule for names that arrive from another Mac. A name that fails declines the whole offer.
public enum FlingNames {
    private static let forbidden: Set<Character> = ["/", "\\", ":"]

    private static func hasControl(_ name: String) -> Bool {
        name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// Format characters (bidi overrides, zero width and byte order marks) can make a name read as another extension.
    /// The two joiners that emoji sequences need are allowed.
    private static func isDisguiseCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format && scalar != "\u{200C}" && scalar != "\u{200D}"
    }

    /// Returns the NFC form of a safe name, or why it is not safe.
    public static func validate(_ name: String) -> Result<String, FlingNameError> {
        let nfc = name.precomposedStringWithCanonicalMapping
        if nfc.isEmpty || nfc == "." || nfc == ".." || nfc.hasPrefix(".") { return .failure(.unsafe) }
        if nfc.contains(where: { forbidden.contains($0) }) || hasControl(nfc) || nfc.unicodeScalars.contains(where: isDisguiseCharacter) {
            return .failure(.unsafe)
        }
        if nfc.utf8.count > FlingLimits.maxNameBytes { return .failure(.tooLong) }
        return .success(nfc)
    }

    /// Turns any local file name into one that passes `validate`; senders use it for their own names. `reserve` leaves
    /// room for text added later (a number and an extension), and `maxBytes` caps the result.
    public static func clean(_ name: String, reserve: Int = 0, maxBytes: Int = FlingLimits.maxNameBytes) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .control || forbidden.contains(Character(scalar)) || isDisguiseCharacter(scalar) {
                scalars.append("_")
            } else {
                scalars.append(scalar)
            }
        }
        var text = String(scalars)
        while text.hasPrefix(".") { text.removeFirst() }
        let limit = max(1, min(maxBytes, FlingLimits.maxNameBytes) - reserve)
        if text.utf8.count > limit {
            // Keep a short extension and shorten the stem.
            let ns = text as NSString
            let ext = ns.pathExtension
            let keep = (!ext.isEmpty && ext.utf8.count <= 16) ? "." + ext : ""
            var stem = keep.isEmpty ? text : ns.deletingPathExtension
            while !stem.isEmpty && stem.utf8.count + keep.utf8.count > limit { stem.removeLast() }
            text = stem.isEmpty ? String(text.prefix(1)) : stem + keep
        }
        return text.isEmpty ? "File" : text
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// `a.png` -> `a 2.png`, `a 3.png`, and so on until the name is not in `taken`. Names that differ only in case or
    /// character width count as taken (APFS is usually case-insensitive), and the result never exceeds 255 bytes.
    public static func freeName(_ name: String, taken: Set<String>) -> String {
        let folded = Set(taken.map(fold))
        guard folded.contains(fold(name)) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let tail = ext.isEmpty ? " \(n)" : " \(n).\(ext)"
            var head = stem
            while head.utf8.count + tail.utf8.count > FlingLimits.maxNameBytes && !head.isEmpty { head.removeLast() }
            let candidate = head + tail
            if !folded.contains(fold(candidate)) { return candidate }
            n += 1
        }
    }

    /// True when `url` is strictly inside `root` after resolving `.` and `..`.
    public static func isContained(_ url: URL, in root: URL) -> Bool {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/") && path != base
    }
}
