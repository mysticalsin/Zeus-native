import Testing
import ZeusCore

@Suite struct SettingsKeyContributionTests {
    @Test func duplicateIDsAcrossCatalogAndContributionsFail() {
        let catalog = ["general.language", "about.autoUpdate"]
        let contributions = [
            SettingsKeyContribution(id: "general.language", defaultValue: "English", kind: .text, policy: .exportable),
            SettingsKeyContribution(id: "media.level", defaultValue: "1", kind: .number, policy: .localOnly),
            SettingsKeyContribution(id: "media.level", defaultValue: "2", kind: .number, policy: .localOnly),
        ]
        let problems = SettingsKeyLedger.problems(catalogIDs: catalog, contributions: contributions)
        #expect(problems.contains { $0.contains("general.language") })
        #expect(problems.contains { $0.contains("media.level") })
    }

    @Test func aRoundTripPersists() {
        let item = SettingsKeyContribution(id: "portal.city", defaultValue: "Home", kind: .text, policy: .exportable)
        var stored: [String: String] = [:]
        #expect(SettingsKeyLedger.load(item, stored: stored[item.id]) == "Home")
        #expect(SettingsKeyLedger.save(&stored, item, "Away"))
        #expect(stored[item.id] == "Away")
        #expect(SettingsKeyLedger.load(item, stored: stored[item.id]) == "Away")
    }

    @Test func exportOmitsLocalOnlyAndSecretKeys() {
        let exported = SettingsKeyContribution(id: "media.name", defaultValue: "", kind: .text, policy: .exportable)
        let local = SettingsKeyContribution(id: "battery.seen", defaultValue: "false", kind: .toggle, policy: .localOnly)
        let held = SettingsKeyContribution(id: "face.presence", defaultValue: "false", kind: .toggle, policy: .importCannotEnable)
        let secret = SettingsKeyContribution(id: "license.key", defaultValue: "", kind: .text, policy: .secretNeverStored)
        let stored = [exported.id: "Desk", local.id: "true", held.id: "false", secret.id: "sk-live-abcdefghijklmnopqrstuvwxyz"]
        let out = SettingsKeyLedger.exportMap(stored: stored, contributions: [exported, local, held, secret])
        #expect(out[exported.id] == "Desk")
        #expect(out[held.id] == "false")
        #expect(out[local.id] == nil)
        #expect(out[secret.id] == nil)
    }

    @Test func importCannotEnableAnImportCannotEnableKey() {
        let item = SettingsKeyContribution(id: "face.presence", defaultValue: "false", kind: .toggle, policy: .importCannotEnable)
        #expect(SettingsKeyLedger.imported(item, current: "false", incoming: "true") == nil)
        #expect(SettingsKeyLedger.imported(item, current: "true", incoming: "false") == "false")
        #expect(SettingsKeyLedger.imported(item, current: "true", incoming: "true") == "true")
    }

    @Test func aSecretLookingValueIsRejected() {
        let item = SettingsKeyContribution(id: "media.token", defaultValue: "", kind: .text, policy: .exportable)
        let secret = SettingsKeyContribution(id: "license.key", defaultValue: "", kind: .text, policy: .secretNeverStored)
        #expect(!SettingsKeyLedger.mayStore(item, value: "sk-live-abcdefghijklmnopqrstuvwxyz"))
        #expect(SettingsKeyLedger.mayStore(item, value: "Desk"))
        #expect(!SettingsKeyLedger.mayStore(secret, value: "Desk"))
    }

    @Test func aFilledSlotKeyMustBeADeclaredContribution() {
        let slot = GlassSectionSlot(id: "glass.battery", title: "Battery", filled: true, keys: ["battery.mutant"], order: 2, placement: .topbarTab(2))
        let missing = GlassSectionManifest.keysMissingFrom(slot, contributions: [])
        #expect(missing == ["battery.mutant"])
        let declared = [SettingsKeyContribution(id: "battery.mutant", defaultValue: "0", kind: .number, policy: .localOnly)]
        let registered = GlassSectionManifest.keysMissingFrom(slot, contributions: declared)
        #expect(registered.isEmpty)
        #expect(GlassSectionManifest.unregisteredSlotKeys().isEmpty)
    }

    @Test func everyContributionIDIsUniqueAndHasADefault() {
        let live = SettingsKeyLedger.problems(catalogIDs: ["general.language"], contributions: GlassSectionManifest.keyContributions)
        #expect(live.isEmpty)
        let blank = SettingsKeyContribution(id: " ", defaultValue: "false", kind: .toggle, policy: .localOnly)
        let problems = SettingsKeyLedger.problems(catalogIDs: [], contributions: [blank])
        #expect(!problems.isEmpty)
        let item = SettingsKeyContribution(id: "focus.mode", defaultValue: "off", kind: .choice, policy: .exportable)
        #expect(SettingsKeyLedger.load(item, stored: nil) == "off")
    }
}
