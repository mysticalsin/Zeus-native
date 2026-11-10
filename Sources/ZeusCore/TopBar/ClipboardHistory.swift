import Foundation

/// What a clipboard item is.
public enum ClipboardKind: String, Codable, Sendable { case text, link, image, file }

/// The chips on the Clipboard page.
public enum ClipboardFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", text = "Text", links = "Links", images = "Images", files = "Files"
    public var id: String { rawValue }

    public func includes(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .all: true
        case .text: entry.kind == .text && !entry.isImageHint
        case .links: entry.kind == .link
        case .images: entry.kind == .image || (entry.kind == .text && entry.isImageHint)
        case .files: entry.kind == .file
        }
    }
}

public struct ClipboardEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// For text: the text. For an image: "Image 640 x 480". For files: their names, comma separated.
    public var text: String
    public var date: Date
    public var sourceApp: String?
    public var pinned: Bool
    /// Name of the saved image in the clipboard image cache (a content hash), for image items.
    public var imageFile: String?
    public var imageWidth: Int = 0
    public var imageHeight: Int = 0
    /// Absolute paths, for file items.
    public var filePaths: [String] = []

    public init(id: UUID = UUID(), text: String, date: Date = Date(), sourceApp: String? = nil, pinned: Bool = false,
                imageFile: String? = nil, imageWidth: Int = 0, imageHeight: Int = 0, filePaths: [String] = []) {
        self.id = id
        self.text = text
        self.date = date
        self.sourceApp = sourceApp
        self.pinned = pinned
        self.imageFile = imageFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
    }

    public var kind: ClipboardKind {
        if imageFile != nil { return .image }
        if !filePaths.isEmpty { return .file }
        return isLink ? .link : .text
    }

    /// What makes two copies "the same item", so a repeat moves to the top instead of adding a row.
    var identityKey: String {
        switch kind {
        case .image: "image:" + (imageFile ?? "")
        case .file: "file:" + filePaths.joined(separator: "\n")
        default: "text:" + text
        }
    }

    /// One trimmed line for the notch list.
    public var preview: String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 120 ? String(trimmed.prefix(119)) + "…" : trimmed
    }

    /// Glance Clipboard filters: Links vs Text. Images are a separate pasteboard type; text that
    /// only names an image file is tagged so the Images chip still has something to show.
    public var isLink: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    public var isImageHint: Bool {
        let lower = text.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".gif") || lower.hasSuffix(".webp") || lower.hasSuffix(".heic")
    }
}

/// Recent copies, newest first. Copying the same text again moves it to the top instead of
/// adding a duplicate; pinned entries survive the size limit and "Clear".
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [ClipboardEntry] = []
    public var limit: Int

    public init(limit: Int = 60) { self.limit = limit }

    /// Returns false when the text is empty or would be a pure whitespace entry.
    @discardableResult
    public mutating func add(_ text: String, sourceApp: String? = nil, at date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 200_000 else { return false }
        insert(ClipboardEntry(text: text, date: date, sourceApp: sourceApp))
        return true
    }

    /// An image copy. `imageFile` is the saved file's name; the same picture copied twice is one item.
    @discardableResult
    public mutating func addImage(file: String, width: Int, height: Int, sourceApp: String? = nil, at date: Date = Date()) -> Bool {
        guard !file.isEmpty else { return false }
        insert(ClipboardEntry(text: "Image \(width) \u{00D7} \(height)", date: date, sourceApp: sourceApp, imageFile: file, imageWidth: width, imageHeight: height))
        return true
    }

    /// Files copied in Finder (or anywhere that puts file URLs on the pasteboard).
    @discardableResult
    public mutating func addFiles(_ paths: [String], sourceApp: String? = nil, at date: Date = Date()) -> Bool {
        let paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return false }
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let label = names.count > 3 ? names.prefix(3).joined(separator: ", ") + " +\(names.count - 3)" : names.joined(separator: ", ")
        insert(ClipboardEntry(text: label, date: date, sourceApp: sourceApp, filePaths: paths))
        return true
    }

    private mutating func insert(_ entry: ClipboardEntry) {
        var entry = entry
        if let index = entries.firstIndex(where: { $0.identityKey == entry.identityKey }) {
            entry.pinned = entries[index].pinned
            entries.remove(at: index)
        }
        entries.insert(entry, at: 0)
        trim()
    }

    /// The saved image names still in use, so the image cache can drop the rest.
    public var imageFilesInUse: Set<String> { Set(entries.compactMap(\.imageFile)) }

    public mutating func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    public mutating func clear() { entries.removeAll { !$0.pinned } }

    public func search(_ query: String) -> [ClipboardEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    private mutating func trim() {
        while entries.count > limit, let last = entries.lastIndex(where: { !$0.pinned }) {
            entries.remove(at: last)
        }
    }
}
