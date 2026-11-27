import Foundation

/// An http or https page address. A missing scheme gets https. A mail link, a script, or a file does not.
public enum WebAddress {
    public static func page(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            let lowered = text.lowercased()
            guard !lowered.hasPrefix("javascript:"), !lowered.hasPrefix("data:") else { return nil }
            let head = lowered.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let name = head.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            // A colon here is a port, as in localhost:3000. mailto: and about: are not hosts.
            if head.contains(":") {
                guard name == "localhost" || name.contains(".") else { return nil }
            }
            guard name == "localhost" || text.contains(".") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return text
    }
}
