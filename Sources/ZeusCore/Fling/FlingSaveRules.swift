import Foundation

public enum FlingSaveMode: String, Codable, CaseIterable, Sendable {
    case downloads, clipboard, ask
}

/// Where arrivals go and how links are kept.
public enum FlingSaveRules {
    /// The stack folder for one arrival. Only the Downloads mode with Downloads access lands in `<root>/Fling`;
    /// every other case lands in the private inbox, so nothing is lost and nothing asks for access on its own.
    public static func destination(mode: FlingSaveMode, root: URL, inbox: URL, peer: String, date: Date,
                                   downloadsGranted: Bool, timeZone: TimeZone = .current) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let trimmed = peer.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = "\(trimmed.isEmpty ? "Mac" : FlingNames.clean(trimmed)) \(formatter.string(from: date))"
        if mode == .downloads && downloadsGranted {
            return root.appendingPathComponent("Fling", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        }
        return inbox.appendingPathComponent(name, isDirectory: true)
    }

    /// True for a path inside a folder named Fling; the screenshot watcher uses it to ignore Fling arrivals.
    public static func isInsideFlingFolder(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.dropLast().contains("Fling")
    }

    /// A received link is kept as a `.webloc` file, which Finder opens in the browser.
    public static func weblocData(for link: String) -> Data {
        (try? PropertyListSerialization.data(fromPropertyList: ["URL": link], format: .xml, options: 0)) ?? Data()
    }

    public static func linkFileName(_ title: String) -> String { FlingNames.clean(title) + ".webloc" }
}
