import Foundation
import Testing
@testable import ZeusCore

@Suite("Private password files")
struct PrivateFileModeTests {
    @Test func groupOrOtherAccessIsRefused() {
        #expect(PrivateFileMode.accepts(0o600))
        #expect(!PrivateFileMode.accepts(0o640))
        #expect(!PrivateFileMode.accepts(0o644))
        #expect(!PrivateFileMode.accepts(0o660))
        #expect(!PrivateFileMode.accepts(0o604))
    }
}
