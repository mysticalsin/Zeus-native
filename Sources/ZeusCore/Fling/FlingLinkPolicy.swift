import Darwin
import Foundation

/// Which received links may open in the browser without a click. A paired Mac can send a link, but it must not be
/// able to make this Mac request a page on its own network, so only public web addresses open by themselves.
public enum FlingLinkPolicy {
    public static func opensWithoutAClick(_ text: String) -> Bool {
        guard FlingOfferRules.isWebLink(text), let components = URLComponents(string: text), var host = components.host?.lowercased() else { return false }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if host.contains(":") { return isPublicIPv6(host) }
        // Anything made of digits, hex letters and dots that is not a plain dotted quad is a number in disguise.
        if host.allSatisfy({ "0123456789abcdefx.".contains($0) }) && host.contains(where: { $0.isNumber || $0 == "x" }) {
            return isPublicIPv4(host)
        }
        guard host.contains(".") else { return false }
        for suffix in [".local", ".localhost", ".internal", ".lan", ".home", ".home.arpa", ".corp", ".intranet"] where host.hasSuffix(suffix) { return false }
        return host != "localhost"
    }

    private static func isPublicIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let n = Int(part), n <= 255 else { return false }
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
