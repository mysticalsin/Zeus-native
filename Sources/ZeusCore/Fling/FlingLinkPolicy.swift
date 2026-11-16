import Darwin
import Foundation

/// Which received links may open in the browser without a click. A paired Mac can send a link, but it must not be
/// able to make this Mac request a page on its own network, so only public web addresses open by themselves.
/// DNS rebinding (a public name that later answers with a private address) cannot be seen from the name and is an
/// accepted risk, written down in docs/FLING.md.
public enum FlingLinkPolicy {
    /// DNS suffixes whose names answer with whatever address is written in them, so they can point anywhere.
    static let wildcardSuffixes = ["nip.io", "sslip.io", "xip.io", "localtest.me", "lvh.me"]

    public static func opensWithoutAClick(_ text: String) -> Bool { urlToOpen(text) != nil }

    /// The URL to hand to the browser, or nil. It is the same URL whose host was checked, so what is opened is what
    /// was judged, and the host must be plain ASCII after the URL was parsed.
    public static func urlToOpen(_ text: String) -> URL? {
        guard FlingOfferRules.isWebLink(text), let url = URL(string: text), var host = url.host?.lowercased() else { return nil }
        // The part before the path must already be plain ASCII: a name that only becomes ASCII after mapping (full
        // width letters, accents, percent escapes) is refused rather than trusted.
        guard let schemeEnd = text.range(of: "://") else { return nil }
        let authority = text[schemeEnd.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard authority.unicodeScalars.allSatisfy({ $0.isASCII && $0 != "%" }) else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ $0.isASCII && ("a"..."z" ~= $0 || "0"..."9" ~= $0 || $0 == "." || $0 == "-" || $0 == ":") }) else { return nil }
        return isPublic(host) ? url : nil
    }

    private static func isPublic(_ host: String) -> Bool {
        if host.contains(":") { return isPublicIPv6(host) }
        // Anything made of digits, hex letters and dots that is not a plain dotted quad is a number in disguise.
        if host.allSatisfy({ "0123456789abcdefx.".contains($0) }) && host.contains(where: { $0.isNumber || $0 == "x" }) {
            return isPublicIPv4(host)
        }
        guard host.contains(".") else { return false }
        for suffix in [".local", ".localhost", ".internal", ".lan", ".home", ".home.arpa", ".corp", ".intranet"] where host.hasSuffix(suffix) { return false }
        if host == "localhost" { return false }
        for suffix in wildcardSuffixes where host == suffix || host.hasSuffix("." + suffix) { return false }
        return !embedsPrivateAddress(host)
    }

    /// A name such as 192-168-1-1.example.com or x.10.0.0.5.example.org that spells out a private address.
    private static func embedsPrivateAddress(_ host: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})[.-](\d{1,3})[.-](\d{1,3})[.-](\d{1,3})"#) else { return true }
        let range = NSRange(host.startIndex..., in: host)
        for match in regex.matches(in: host, range: range) {
            let octets = (1...4).compactMap { Range(match.range(at: $0), in: host).flatMap { Int(host[$0]) } }
            if octets.count == 4, octets.allSatisfy({ $0 <= 255 }), isPrivate(octets) { return true }
        }
        return false
    }

    private static func isPublicIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            // Canonical decimal only: no leading zeros (they read as octal elsewhere), no hex, no short forms.
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  part == "0" || part.first != "0", let n = Int(part), n <= 255 else { return false }
            octets.append(n)
        }
        return !isPrivate(octets)
    }

    private static func isPrivate(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true // carrier-grade NAT
        case (let a, _) where a >= 224: return true // multicast and reserved
        default: return false
        }
    }

    private static func isPublicIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
        let b = withUnsafeBytes(of: address) { Array($0) }
        if b.allSatisfy({ $0 == 0 }) { return false } // ::
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return false } // ::1
        if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return false } // fe80::/10
        if (b[0] & 0xfe) == 0xfc { return false } // fc00::/7
        if b[0] == 0xff { return false } // multicast
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff { return !isPrivate([Int(b[12]), Int(b[13]), Int(b[14]), Int(b[15])]) } // v4-mapped
        if b[0..<12].allSatisfy({ $0 == 0 }) { return false } // v4-compatible
        return true
    }
}
