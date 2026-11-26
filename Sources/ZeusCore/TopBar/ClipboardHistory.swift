import Foundation

/// What a clipboard item is.
public enum ClipboardKind: String, Codable, Sendable { case text, link, image, file }

/// The chips on the Clipboard page.
public enum ClipboardFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", text = "Text", links = "Links", images = "Images", files = "Files"
    public var id: String { rawValue }

    public func includes(_ entry: ClipboardEntry) -> Bool {
        ClipboardHistoryBox.includes(filter: self, kind: entry.kind, isImageHint: entry.isImageHint)
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
        ClipboardHistoryBox.kind(imageFile: imageFile, filePaths: filePaths, text: text)
    }

    /// What makes two copies "the same item", so a repeat moves to the top instead of adding a row.
    var identityKey: String {
        ClipboardHistoryBox.identityKey(kind: kind, imageFile: imageFile, filePaths: filePaths, text: text)
    }

    /// One trimmed line for the notch list.
    public var preview: String {
        ClipboardHistoryBox.preview(text)
    }

    /// Glance Clipboard filters: Links vs Text. Images are a separate pasteboard type; text that
    /// only names an image file is tagged so the Images chip still has something to show.
    public var isLink: Bool {
        ClipboardHistoryBox.isLink(text)
    }

    public var isImageHint: Bool {
        ClipboardHistoryBox.isImageHint(text)
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
        guard ClipboardHistoryBox.canAddText(text) else { return false }
        insert(ClipboardEntry(text: text, date: date, sourceApp: sourceApp))
        return true
    }

    /// An image copy. `imageFile` is the saved file's name; the same picture copied twice is one item.
    @discardableResult
    public mutating func addImage(file: String, width: Int, height: Int, sourceApp: String? = nil, at date: Date = Date()) -> Bool {
        guard ClipboardHistoryBox.canAddImage(file: file) else { return false }
        insert(ClipboardEntry(
            text: ClipboardHistoryBox.imageLabel(width: width, height: height),
            date: date, sourceApp: sourceApp, imageFile: file, imageWidth: width, imageHeight: height))
        return true
    }

    /// Files copied in Finder (or anywhere that puts file URLs on the pasteboard).
    @discardableResult
    public mutating func addFiles(_ paths: [String], sourceApp: String? = nil, at date: Date = Date()) -> Bool {
        let paths = ClipboardHistoryBox.nonemptyPaths(paths)
        guard !paths.isEmpty else { return false }
        insert(ClipboardEntry(text: ClipboardHistoryBox.fileLabel(paths), date: date, sourceApp: sourceApp, filePaths: paths))
        return true
    }

    private mutating func insert(_ entry: ClipboardEntry) {
        var entry = entry
        if let index = ClipboardHistoryBox.duplicateIndex(keys: entries.map(\.identityKey), key: entry.identityKey) {
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
        entries.filter { ClipboardHistoryBox.matchesSearch(text: $0.text, query: query) }
    }

    private mutating func trim() {
        while let last = ClipboardHistoryBox.trimIndex(count: entries.count, limit: limit, pinned: entries.map(\.pinned)) {
            entries.remove(at: last)
        }
    }
}
