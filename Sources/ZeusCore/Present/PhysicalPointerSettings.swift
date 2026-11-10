import Foundation

/// L5: physical pointer actuation (synthetic clicks) stays off unless Tony turns it on.
public enum PhysicalPointerSettings {
    public static let defaultsKey = "present.physicalPointer"

    public static var enabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false
    }
}
