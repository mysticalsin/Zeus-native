import Foundation

/// Kind, identity, preview, and the list rules for clipboard history.
/// The caller supplies the text, the paths, and the saved rows.
/// This type does not read a pasteboard, a screen, a pointer, a clock, or a stored setting.
public enum ClipboardHistoryBox {
    /// Copies longer than this are dropped. The count is the raw string, before trimming.
    public static let textLimit = 200_000
    /// A preview longer than this keeps the first 119 characters and an ellipsis.
    public static let previewLimit = 120
    /// File names shown before the "+N" tail.
    public static let fileNameLimit = 3

    /// False for a blank copy, or one past `textLimit`.
    public static func canAddText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= textLimit
    }

    /// An image copy needs a saved file name. A name of spaces still counts.
    public static func canAddImage(file: String) -> Bool {
        !file.isEmpty
    }

    /// An image file wins, then any stored path, then a link, then plain text.
    /// An empty path string is still a path. A missing image file is not an image.
    public static func kind(imageFile: String?, filePaths: [String], text: String) -> ClipboardKind {
        if imageFile != nil { return .image }
        if !filePaths.isEmpty { return .file }
        return isLink(text) ? .link : .text
    }

    public static func identityKey(kind: ClipboardKind, imageFile: String?, filePaths: [String], text: String) -> String {
        switch kind {
        case .image: "image:" + (imageFile ?? "")
        case .file: "file:" + filePaths.joined(separator: "\n")
        default: "text:" + text
        }
    }

    /// One line for the notch list. Newlines become spaces, and a line past the cap ends with an ellipsis.
    public static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return trimmed.count > previewLimit ? String(trimmed.prefix(previewLimit - 1)) + "…" : trimmed
    }

    public static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    public static func isImageHint(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".gif") || lower.hasSuffix(".webp") || lower.hasSuffix(".heic")
    }

    public static func includes(filter: ClipboardFilter, kind: ClipboardKind, isImageHint: Bool) -> Bool {
        switch filter {
        case .all: true
        case .text: kind == .text && !isImageHint
        case .links: kind == .link
        case .images: kind == .image || (kind == .text && isImageHint)
        case .files: kind == .file
        }
    }

    public static func imageLabel(width: Int, height: Int) -> String {
        "Image \(width) \u{00D7} \(height)"
    }

    public static func nonemptyPaths(_ paths: [String]) -> [String] {
        paths.filter { !$0.isEmpty }
    }

    /// Last path component of each path. More than three names keep the first three and a "+N" tail.
    public static func fileLabel(_ paths: [String]) -> String {
        let names = paths.map { ($0 as NSString).lastPathComponent }
        return names.count > fileNameLimit
            ? names.prefix(fileNameLimit).joined(separator: ", ") + " +\(names.count - fileNameLimit)"
            : names.joined(separator: ", ")
    }

    /// The first row with this identity, so a repeat moves to the top instead of adding another.
    public static func duplicateIndex(keys: [String], key: String) -> Int? {
        keys.firstIndex(of: key)
    }

    /// Last unpinned row while the list is over the limit. Nil when the list fits, or every row is pinned.
    public static func trimIndex(count: Int, limit: Int, pinned: [Bool]) -> Int? {
        guard count > limit else { return nil }
        return pinned.lastIndex(where: { !$0 })
    }

    /// Blank after trimming spaces means the whole list. Newlines are not trimmed here.
    public static func normalizedSearch(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces)
    }

    public static func matchesSearch(text: String, query: String) -> Bool {
        let q = normalizedSearch(query)
        guard !q.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(q)
    }
}
