import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads a feed into candidates. It does not install, and it does not accept a pre-release version.
public enum UpdateFeedDocument {
    public static func candidates(from data: Data) -> Result<[UpdateCandidate], UpdateFailureReason> {
        if data.isEmpty || data.count > UpdateFeedPolicy.maximumFeedBytes { return .failure(.unreadable) }
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.unreadable) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return jsonCandidates(data) }
        if trimmed.hasPrefix("<") { return .success(appcastCandidates(data)) }
        return .failure(.unreadable)
    }

    public static func best(_ items: [UpdateCandidate]) -> UpdateCandidate? {
        items.max { lhs, rhs in
            if lhs.version != rhs.version { return lhs.version < rhs.version }
            return lhs.edSignature.isEmpty && !rhs.edSignature.isEmpty
        }
    }

    private static func jsonCandidates(_ data: Data) -> Result<[UpdateCandidate], UpdateFailureReason> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.unreadable) }
        guard let rawVersion = json["version"] as? String, let version = UpdateVersions.release(rawVersion) else {
            return .success([])
        }
        guard let link = json["downloadURL"] as? String, let url = URL(string: link) else { return .success([]) }
        let signature = (json["edSignature"] as? String) ?? ""
        let notes = (json["notes"] as? [String]) ?? []
        return .success([UpdateCandidate(version: version, downloadURL: url, edSignature: signature, notes: Array(notes.prefix(20)))])
    }

    private static func appcastCandidates(_ data: Data) -> [UpdateCandidate] {
        let parser = AppcastFeedParser()
        let reader = XMLParser(data: data)
        reader.shouldProcessNamespaces = false
        reader.delegate = parser
        guard reader.parse() else { return [] }
        var items: [UpdateCandidate] = []
        for item in parser.items.prefix(32) {
            let notes = UpdateFeedNotes.lines(item.notes)
            for enclosure in item.enclosures {
                let raw = firstVersion(enclosure.shortVersion, enclosure.version, item.shortVersion, item.version)
                guard let version = UpdateVersions.release(raw), let url = URL(string: enclosure.url), !enclosure.url.isEmpty else { continue }
                items.append(UpdateCandidate(
                    version: version,
                    downloadURL: url,
                    edSignature: enclosure.signature.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes
                ))
            }
        }
        return items
    }

    private static func firstVersion(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }
}

enum UpdateFeedNotes {
    static func lines(_ raw: String) -> [String] {
        var text = raw.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<li>", with: "", options: .caseInsensitive)
        var plain = ""
        var inside = false
        for character in text {
            if character == "<" { inside = true; continue }
            if character == ">" { inside = false; continue }
            if !inside { plain.append(character) }
        }
        return plain.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(20)
            .map { String($0.prefix(240)) }
    }
}

private final class AppcastFeedParser: NSObject, XMLParserDelegate {
    struct Enclosure {
        var url = ""
        var signature = ""
        var version = ""
        var shortVersion = ""
    }

    struct Item {
        var version = ""
        var shortVersion = ""
        var notes = ""
        var enclosures: [Enclosure] = []
    }

    var items: [Item] = []
    private var current: Item?
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        buffer = ""
        if elementName == "item" { current = Item() }
        guard elementName == "enclosure", var item = current else { return }
        item.enclosures.append(Enclosure(
            url: attributeDict["url"] ?? "",
            signature: attributeDict["sparkle:edSignature"] ?? attributeDict["edSignature"] ?? "",
            version: attributeDict["sparkle:version"] ?? attributeDict["version"] ?? "",
            shortVersion: attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"] ?? ""
        ))
        current = item
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { buffer += text }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if var item = current {
            if elementName.hasSuffix("shortVersionString") {
                item.shortVersion = text
            } else if elementName == "version" || elementName == "sparkle:version" {
                item.version = text
            } else if elementName.hasSuffix("description") {
                item.notes = buffer
            }
            current = item
            if elementName == "item" {
                items.append(item)
                current = nil
            }
        }
        buffer = ""
    }
}

/// Loads a feed only from HTTPS. An insecure address never opens a connection.
public enum UpdateFeedTransport {
    public static func load(_ url: URL) async -> Result<Data, UpdateFailureReason> {
        guard UpdateFeedPolicy.isSecure(url) else { return .failure(.insecureFeed) }
        let session = URLSession(configuration: .ephemeral, delegate: HTTPSOnlyRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.url.map(UpdateFeedPolicy.isSecure) == true else { return .failure(.network) }
            guard data.count <= UpdateFeedPolicy.maximumFeedBytes else { return .failure(.unreadable) }
            return .success(data)
        } catch {
            return .failure(.network)
        }
    }
}
