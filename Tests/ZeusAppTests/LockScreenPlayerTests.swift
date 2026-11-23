import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Lock screen player")
struct LockScreenPlayerTests {
    @Test func aMissingPrivateSpaceStaysUnavailableAndCreatesNoWindow() {
        let suite = NSTemporaryDirectory() + "LockScreenPlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        var created = false
        let controller = LockScreenPlayerController(model: model, spaceAvailable: { false }, createSpace: {
            created = true
            return false
        })
        controller.setEnabled(true)
        #expect(model.lockScreenPlayer == .unavailable)
        #expect(!created)
        controller.setEnabled(false)
        #expect(model.lockScreenPlayer == .off)
    }

    @Test func aSpaceThatIgnoresInputCanBeShown() {
        let suite = NSTemporaryDirectory() + "LockScreenPlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        var created = false
        let controller = LockScreenPlayerController(model: model, spaceAvailable: { true }, createSpace: {
            created = true
            return true
        })
        controller.setEnabled(true)
        #expect(created)
        #expect(model.lockScreenPlayer == .shown)
    }
}
