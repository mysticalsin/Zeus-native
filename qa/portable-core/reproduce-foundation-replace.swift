import Foundation

// Isolated Foundation diagnostic. It only touches a new temporary test directory.
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("zeus-replace-check-\(UUID())")
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
let original = root.appendingPathComponent("original.json")
let temporary = root.appendingPathComponent("replacement.tmp")
try Data("old".utf8).write(to: original)
try Data("new".utf8).write(to: temporary)
do {
    _ = try manager.replaceItemAt(original, withItemAt: temporary)
    print("Replacement:", try String(contentsOf: original, encoding: .utf8))
} catch {
    print("replaceItemAt failed:", error)
    print("Original exists:", manager.fileExists(atPath: original.path))
    print("Temporary exists:", manager.fileExists(atPath: temporary.path))
}
