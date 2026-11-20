import Foundation

/// A private-call table is kept only when every name resolves to a non-zero address. Nothing here calls an address.
public enum LockScreenSymbolGate {
    public static func table(names: [String], lookup: (String) -> UInt?) -> [String: UInt]? {
        guard !names.isEmpty, Set(names).count == names.count else { return nil }
        var resolved: [String: UInt] = [:]
        resolved.reserveCapacity(names.count)
        for name in names {
            guard let address = lookup(name), address != 0 else { return nil }
            resolved[name] = address
        }
        return resolved
    }
}
