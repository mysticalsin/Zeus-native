import Foundation

/// L5: physical pointer actuation (synthetic clicks) stays off unless Tony turns it on.
public enum PhysicalPointerSettings {
    public static let defaultsKey = "present.physicalPointer"

    public static var enabled: Bool {
        enabled(storedValue: UserDefaults.standard.object(forKey: defaultsKey) as? Bool)
    }

    /// The preference decision is independent of its host-backed storage.
    public static func enabled(storedValue: Bool?) -> Bool { storedValue ?? false }
}
