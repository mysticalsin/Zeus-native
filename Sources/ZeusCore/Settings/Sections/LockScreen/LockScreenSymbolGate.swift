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

/// Turns a symbol table into the answer the player card reads. A resolved table that is not called
/// can show the card. A missing table hides it. Calling an unverified symbol is a failed call.
public enum LockScreenSpaceProbe {
    public static func answer(resolved: Bool, invokesUnverifiedSymbols: Bool) -> LockScreenSpaceAnswer {
        guard resolved else { return .symbolMissing }
        return invokesUnverifiedSymbols ? .callFailed : .shown
    }
}
