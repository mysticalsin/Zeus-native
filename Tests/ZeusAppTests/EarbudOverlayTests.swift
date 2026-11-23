import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Earbud overlay")
struct EarbudOverlayTests {
    @Test func aFoundDeviceReachesTheNotchModelAndStoppingClearsIt() {
        let suite = NSTemporaryDirectory() + "EarbudOverlayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        let controller = EarbudOverlayController(model: model, scan: {
            EarbudOverlayRule.reading(name: "Buds", audio: true, connected: true, left: 80, right: 70, casePercent: 50)
        })
        controller.setEnabled(true)
        #expect(model.earbud == EarbudReading(name: "Buds", left: 80, right: 70, casePercent: 50))
        #expect(model.earbudShownAt != nil)
        controller.setEnabled(false)
        #expect(model.earbud == nil)
        #expect(model.earbudShownAt == nil)
    }
}
