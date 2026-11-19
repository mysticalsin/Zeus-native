import Foundation

// MARK: Grouping

/// One app's alerts on the Alerts page, newest first.
public struct AlertGroup: Equatable, Identifiable, Sendable {
    public var appID: String
    public var appName: String
    public var items: [MirroredNotification]
    public var id: String { appID }
    public var newest: Date { items.map(\.date).max() ?? .distantPast }
}

public enum AlertGrouping {
    /// Groups by app (case-insensitive id). Groups are ordered by their newest alert; rows inside by date, newest first.
    public static func groups(_ items: [MirroredNotification], appName: (String) -> String) -> [AlertGroup] {
        var order: [String] = []
        var byApp: [String: [MirroredNotification]] = [:]
        for item in items.sorted(by: { $0.date > $1.date }) {
            let key = item.app.lowercased()
            if byApp[key] == nil { order.append(key) }
            byApp[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let list = byApp[key], let first = list.first else { return nil }
            return AlertGroup(appID: first.app, appName: appName(first.app), items: list)
        }
    }
}

// MARK: Relative time

public enum AlertRelativeTime {
    /// "now", "2m", "3h", "2d". Short so it sits in a fixed monospaced-digit column.
    public static func text(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(max(1, Int((seconds / 60).rounded())))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}

// MARK: Icon pixels

public enum AlertIconPixels {
    /// True when a rasterised icon has (almost) no visible pixels. IconServices draws lazily and yields
    /// transparent pixels in a headless or sandboxed process, so "a non-nil image" is not proof of an icon.
    /// `rgba` is 4 bytes per pixel.
    public static func isBlank(rgba: [UInt8], minimumVisibleShare: Double = 0.03) -> Bool {
        let pixels = rgba.count / 4
        guard pixels > 0 else { return true }
        var visible = 0
        var index = 3
        while index < rgba.count {
            if rgba[index] > 40 { visible += 1 }
            index += 4
        }
        return Double(visible) / Double(pixels) < minimumVisibleShare
    }
}

// MARK: Accent

public enum AlertAccent {
    /// The icon's dominant colour as 0xRRGGBB, or nil when the icon has no colourful pixels (greyscale or blank).
    /// Pixels are bucketed into 12 hue sectors weighted by saturation and brightness; the heaviest sector wins.
    /// `rgba` is 4 bytes per pixel, non-premultiplied or premultiplied (alpha only gates visibility).
    public static func dominantHex(rgba: [UInt8]) -> UInt32? {
        var weight = [Double](repeating: 0, count: 12)
        var sums = [[Double]](repeating: [0, 0, 0], count: 12)
        var index = 0
        while index + 3 < rgba.count {
            defer { index += 4 }
            guard rgba[index + 3] > 128 else { continue }
            let r = Double(rgba[index]) / 255, g = Double(rgba[index + 1]) / 255, b = Double(rgba[index + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high == 0 ? 0 : (high - low) / high
            guard saturation > 0.25, high > 0.25 else { continue }
            let delta = high - low
            var hue: Double
            if high == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if high == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            if hue < 0 { hue += 6 }
            let bucket = min(11, Int(hue * 2))
            let w = saturation * high
            weight[bucket] += w
            sums[bucket][0] += r * w; sums[bucket][1] += g * w; sums[bucket][2] += b * w
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 1 else { return nil }
        func channel(_ value: Double) -> UInt32 { UInt32(max(0, min(255, (value / weight[best] * 255).rounded()))) }
        return channel(sums[best][0]) << 16 | channel(sums[best][1]) << 8 | channel(sums[best][2])
    }
}

// MARK: Fallback glyph

public enum AlertAppGlyph {
    /// An SF Symbol for well-known apps, used when the real icon cannot be drawn.
    public static func symbol(for bundleID: String) -> String {
        switch bundleID.lowercased() {
        case "com.apple.mobilesms": "message.fill"
        case "com.apple.mail": "envelope.fill"
        case "com.apple.ical": "calendar"
        case "com.apple.reminders": "checklist"
        case "com.apple.facetime": "video.fill"
        case "com.tinyspeck.slackmacgap": "number"
        case "com.microsoft.teams2", "com.microsoft.teams": "person.2.fill"
        case "com.github.githubclient": "chevron.left.forwardslash.chevron.right"
        default: AppBrandCatalog.glyph(for: bundleID) ?? "app.fill"
        }
    }

}

// MARK: Reply

/// Where "Reply" goes. Only apps with a URL that opens a reply surface get one; for every other app the
/// button is hidden, because a Reply that only opens the item would duplicate Open.
/// Zeus never sends anything: the URL opens a compose box the owner finishes.
public enum AlertReply {
    /// The URL that opens the source app focused on a reply to `item`, or nil when none is known.
    /// Messages needs a phone number or email as the alert title (a display name cannot address a chat).
    /// Mail opens a draft: to the sender when the title is an address, with "Re:" and the subject line.
    /// Slack and Teams deep links need workspace and channel ids an alert does not carry, so they return nil.
    public static func url(for item: AlertItem) -> URL? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.appID.lowercased() {
        case "com.apple.mobilesms":
            guard isAddress(title) else { return nil }
            return URL(string: "imessage:" + encode(title))
        case "com.apple.mail":
            let subject = firstLine(item.body)
            let recipient = title.contains("@") && isAddress(title) ? title : ""
            guard !recipient.isEmpty || !subject.isEmpty else { return nil }
            var text = "mailto:" + encode(recipient)
            if !subject.isEmpty { text += "?subject=" + encode(subject.lowercased().hasPrefix("re:") ? subject : "Re: " + subject) }
            return URL(string: text)
        default:
            return nil
        }
    }

    public static func supportsReply(_ item: AlertItem) -> Bool { url(for: item) != nil }

    static func isAddress(_ text: String) -> Bool {
        if text.contains("@") {
            let parts = text.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !text.contains(" ")
        }
        let digits = text.filter(\.isNumber)
        let allowed = text.allSatisfy { $0.isNumber || "+-() ".contains($0) }
        return allowed && (7...15).contains(digits.count)
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.trimmingCharacters(in: .whitespaces).prefix(120))
    }

    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#+")
        let plain = text.hasPrefix("+") ? String(text.dropFirst()) : text
        return (text.hasPrefix("+") ? "%2B" : "") + (plain.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }
}

// MARK: Motion timings

public enum AlertMotion {
    public static let stretchResponse = 0.42
    public static let stretchDamping = 0.78
    public static let contentStagger = 0.06
    public static let contentStart = 0.30
    public static let sweepDuration = 1.2
    public static let collapseContentFade = 0.1
    public static let reducedFade = 0.12

    /// Seconds after landing at which content item `index` (icon 0, title 1, body 2) starts to appear.
    public static func contentDelay(index: Int) -> Double { contentStart + contentStagger * Double(max(0, index)) }

    /// Whether any alert animation is still running `elapsed` seconds after the capsule appeared.
    /// Past this window the surface owns no animation, display link or timer. Reduce Motion has no window.
    public static func isAnimating(elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        if reduceMotion { return elapsed < reducedFade }
        return elapsed < sweepDuration
    }

    public static func sweepActive(elapsed: TimeInterval, reduceMotion: Bool) -> Bool {
        !reduceMotion && elapsed >= 0 && elapsed < sweepDuration
    }
}
