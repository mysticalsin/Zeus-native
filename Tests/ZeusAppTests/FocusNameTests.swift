import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Focus name")
struct FocusNameTests {
    @Test func aReadableStoreReachesTheFocusPageModelAndStoppingClearsIt() {
        let suite = NSTemporaryDirectory() + "FocusNameTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        let configurations = Data(#"{"data":[{"modeIdentifier":"com.apple.focus.work","mode":{"name":"Work"}}]}"#.utf8)
        let assertions = Data(#"{"data":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}"#.utf8)
        let controller = FocusNameController(model: model, files: {
            FocusNameStore.Files(configurations: configurations, assertions: assertions, permissionDenied: false)
        })
        controller.setEnabled(true)
        #expect(model.systemFocus == .named("Work"))
        controller.setEnabled(false)
        #expect(model.systemFocus == .off)
    }

    @Test func aDeniedStoreSaysItNeedsFullDiskAccess() {
        let suite = NSTemporaryDirectory() + "FocusNameTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TopBarModel(defaults: defaults)
        let controller = FocusNameController(model: model, files: {
            FocusNameStore.Files(configurations: nil, assertions: nil, permissionDenied: true)
        })
        controller.setEnabled(true)
        #expect(model.systemFocus == .needsFullDiskAccess)
    }
}
