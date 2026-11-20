import Foundation

/// Cleans a Focus name or a symbol before anything draws it. Empty and hostile input become nothing.
public enum FocusNameText {
    public static let maxClusters = 64

    public static func cleanName(_ raw: String) -> String? {
        var kept: [Unicode.Scalar] = []
        let scalars = Array(raw.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar.value == 0x200D {
                let next = index + 1 < scalars.count ? scalars[index + 1] : nil
                if let previous = kept.last, previous.properties.isEmoji, let next, next.properties.isEmoji {
                    kept.append(scalar)
                }
                continue
            }
            let category = scalar.properties.generalCategory
            if category == .control || category == .format {
                if scalar.properties.isWhitespace { kept.append(" ") }
                continue
            }
            kept.append(scalar)
        }
        let collapsed = String(String.UnicodeScalarView(kept))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        let clusters = Array(collapsed)
        if clusters.count <= maxClusters { return collapsed }
        return String(clusters.prefix(maxClusters))
    }

    /// A symbol name is a short system-symbol token: lower case, digits, and full stops.
    public static func cleanSymbol(_ raw: String) -> String? {
        guard (1...maxClusters).contains(raw.count) else { return nil }
        let allowed = raw.allSatisfy { character in
            guard character.isASCII else { return false }
            return character.isLowercase || character.isNumber || character == "."
        }
        return allowed ? raw : nil
    }
}
