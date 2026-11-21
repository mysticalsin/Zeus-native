import Foundation
import Testing
@testable import ZeusCore

@Suite("Update install persistence")
struct UpdateInstallPersistenceTests {
    private func fresh() -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.update-install.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func anOwnerInstallChoiceSurvivesLoadAndSave() {
        let defaults = fresh()
        defaults.set("true", forKey: "opt.about.autoInstall")
        #expect(UpdateSettingsStore.load(from: defaults).automaticInstall)
        let state = UpdatePersistedState(
            automaticChecks: true,
            automaticInstall: true,
            lastChecked: nil,
            status: "",
            notes: []
        )
        UpdateSettingsStore.save(state, to: defaults)
        #expect(defaults.string(forKey: "opt.about.autoInstall") == "true")
        #expect(UpdateSettingsStore.load(from: defaults).automaticInstall)
    }
}
