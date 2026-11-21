import Foundation
import Testing
@testable import ZeusCore

@Suite("Provider Keychain update")
struct ProviderKeychainPolicyTests {
    @Test func anUpdateSetsTheSameAccessibilityClassAsAnAdd() {
        #expect(ProviderKeychainPolicy.updateIncludesAccessibility)
    }
}
