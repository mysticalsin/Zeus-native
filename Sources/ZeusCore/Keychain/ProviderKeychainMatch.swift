#if os(macOS)
import Foundation
import Security

/// Generic-password read for the voice provider store. `SecItemCopyMatching` stays in this module.
enum ProviderKeychainMatch {
    static func copyItem(_ query: [String: Any]) -> (status: OSStatus, result: CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
}
#endif
