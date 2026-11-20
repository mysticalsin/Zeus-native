import Darwin
import Foundation
import ZeusCore

/// Loads the window-server symbols and does not call them. A missing symbol hides the card.
enum LockScreenSpaceLoader {
    static let invokesUnverifiedSymbols = false

    static let names = [
        "SLSMainConnectionID",
        "SLSSpaceCreate",
        "SLSSpaceSetAbsoluteLevel",
        "SLSShowSpaces",
        "SLSHideSpaces",
        "SLSSpaceAddWindowsAndRemoveFromSpaces",
        "SLSSpaceDestroy",
    ]

    private static let framework = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    /// Asks whether the symbols are present. It never creates a space.
    static func probe() -> LockScreenSpaceAnswer {
        guard invokesUnverifiedSymbols == false else { return .callFailed }
        let resolved = LockScreenSymbolGate.table(names: names, lookup: lookup)
        return resolved == nil ? .symbolMissing : .callFailed
    }

    private static func lookup(_ name: String) -> UInt? {
        guard let handle = dlopen(framework, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, name) else { return nil }
        return UInt(bitPattern: symbol)
    }
}
