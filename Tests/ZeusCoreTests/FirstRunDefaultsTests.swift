import Foundation
import Testing
@testable import ZeusCore

/// One test per row of `docs/FIRST-RUN-DEFAULTS.md` (except Jev, owned by another branch): a fresh
/// `UserDefaults` suite yields the value the table promises.
@Suite struct FirstRunDefaultsTests {
    private func fresh() -> (UserDefaults, () -> Void) {
        let name = "zeus.firstrun.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func voiceIsUltronAtSixtyPercent() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        #expect(ZeusPersonality.current(defaults) == .ultron)
        #expect(UltronEffectParameters.defaultPercent == 60)
        #expect(!UltronEffectParameters.make(percent: Double(UltronEffectParameters.defaultPercent)).isNeutral)
    }

    @Test func talkToZeusIsFastAnswersWithADeepFollowUp() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        #expect(ModelCap.model(for: .claude, tier: .fast, defaults: defaults) == "haiku")
        #expect(ModelCap.model(for: .claude, tier: .deep, defaults: defaults) == "sonnet")
        #expect(ModelCap.codexVoiceModel == "gpt-6-luna")
        let installed: [BrainEngineID] = [.claude, .codex, .anthropicAPI, .openAIAPI, .gemini]
        #expect(FastTier.fastRace(order: installed, ollamaWarm: false) == [.anthropicAPI, .openAIAPI, .claude, .codex])
        #expect(FastTier.deepEngine(order: installed) == .anthropicAPI)
        #expect(DeepTrigger.reason(for: "think deeper about this", task: .quickAnswer) == .explicit)
    }

    @Test func talkToZeusIsControlOption() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        let talk = ShortcutStore.loadTalk(defaults)
        #expect(talk == .controlOption)
        #expect(!VoiceKey.pointingStartsTurns(talk: talk, pointing: .controlOption, pointingEnabled: true))
    }

    @Test func pointingIsOnWithControlOptionAndDrawWhileHeld() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        #expect(FeatureSettings.pointingEnabled(defaults: defaults))
        #expect(FeatureSettings.pointingDrawWhileHeld(defaults: defaults))
        #expect(FeatureSettings.pointingShortcutName(defaults: defaults) == "Control-Option")
        #expect(Shortcut.controlOption.modifiers == [.control, .option])
    }

    @Test func pointingNeverSendsAScreenshotUntilTheOwnerConsents() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        #expect(!FeatureSettings.pointingSendScreenshot(defaults: defaults))
    }

    @Test func recordSelectsTheMainDisplay() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        let side = RecordlyDisplayChoice.Display(id: 7, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), stableID: "side")
        let main = RecordlyDisplayChoice.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), stableID: "main", isMain: true)
        let decision = RecordlyDisplayChoice.decide(displays: [side, main], current: nil,
                                                    remembered: defaults.string(forKey: "recordly.lastDisplayUUID"))
        #expect(decision.selected == 1)
        #expect(decision.source == .main)
    }

    @Test func callWindowNamesAreOnWhenAccessibilityIsAlreadyGranted() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        #expect(ScribeCallWindowNamesPolicy.isOn(defaults: defaults))
        #expect(ScribeCallWindowNamesPolicy.isActive(accessibilityGranted: true, defaults: defaults))
    }

    @Test func callWindowNamesNeverActivateWithoutAccessibility() {
        let (defaults, cleanup) = fresh(); defer { cleanup() }
        #expect(!ScribeCallWindowNamesPolicy.isActive(accessibilityGranted: false, defaults: defaults))
    }
}
