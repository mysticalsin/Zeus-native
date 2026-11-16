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

    /// Returns the NFC form of a safe name, or why it is not safe.
    public static func validate(_ name: String) -> Result<String, FlingNameError> {
        let nfc = name.precomposedStringWithCanonicalMapping
        if nfc.isEmpty || nfc == "." || nfc == ".." || nfc.hasPrefix(".") { return .failure(.unsafe) }
        if nfc.contains(where: { forbidden.contains($0) }) || hasControl(nfc) || nfc.unicodeScalars.contains("\u{0}") {
            return .failure(.unsafe)
        }
        if nfc.utf8.count > FlingLimits.maxNameBytes { return .failure(.tooLong) }
        return .success(nfc)
    }

    /// Turns any local file name into one that passes `validate`; senders use it for their own names.
    public static func clean(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .control || forbidden.contains(Character(scalar)) {
                scalars.append("_")
            } else {
                scalars.append(scalar)
            }
        }
        var text = String(scalars)
        while text.hasPrefix(".") { text.removeFirst() }
        while text.utf8.count > FlingLimits.maxNameBytes { text.removeLast() }
        return text.isEmpty ? "File" : text
    }

    /// `a.png` -> `a 2.png`, `a 3.png`, and so on until the name is not in `taken`.
    public static func freeName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !taken.contains(candidate) { return candidate }
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
