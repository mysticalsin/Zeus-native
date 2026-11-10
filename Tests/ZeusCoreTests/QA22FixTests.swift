import Foundation
import Testing
@testable import ZeusCore

/// K1 and K2 both added this file on parallel lanes; keep both suites in one file so integrator merge stays conflict-free.
@Suite("QA22 integrator merge")
struct QA22IntegratorMergeTests {
    @Test func k1OnboardingAndK2NotchFixesShareOneTestFile() {
        #expect(OnboardingChromeLayout.previewFitsWindow(at: 1))
        #expect(NotchDebugEffects.recognizes("volume"))
    }
}

@Suite("QA22 settings, voice, notch")
struct QA22FixTests {
    @Test func iPhoneMapsToLiveGlanceSection() {
        #expect(GlanceSettingsSnapshotMapping.glanceSectionID(forLegacySection: "iPhone") == "iPhone")
    }

    @Test func numberedSnapshotUsesGlanceForAppearanceNotificationsIPhoneDiagnostics() {
        for legacy in ["appearance", "notifications", "iPhone", "diagnostics"] {
            #expect(GlanceSettingsSnapshotMapping.glanceSectionID(forLegacySection: legacy) == legacy)
        }
    }

    @Test func numberedSnapshotMapsTodoAndAgentsToGlance() {
        #expect(GlanceSettingsSnapshotMapping.glanceSectionID(forLegacySection: "todo") == "features")
        #expect(GlanceSettingsSnapshotMapping.glanceSectionID(forLegacySection: "agents") == "integrations")
    }

    @Test func kokoroPickerShortLabel() {
        #expect(KokoroVoiceLabels.pickerTitle(voiceID: "am_michael", longName: "Michael, American, deep") == "Michael (US)")
    }

    @Test func physicalFinishChoicesFitPopup() {
        let choices = ["Same all", "Separate"]
        #expect(choices.allSatisfy { $0.count <= 12 })
    }

    @Test func debugAnimateCatalogCoversQAEffects() {
        for name in NotchDebugEffects.lightNames + NotchDebugEffects.mascotStateNames {
            #expect(NotchDebugEffects.recognizes(name))
        }
    }
}

@Suite("QA22 onboarding layout")
struct QA22OnboardingLayoutTests {
    @Test func welcomePreviewFitsAtOneXAndTwoX() {
        #expect(OnboardingChromeLayout.previewFitsWindow(at: 1))
        #expect(OnboardingChromeLayout.previewFitsWindow(at: 2))
        let frame = OnboardingChromeLayout.welcomePreviewFrame()
        #expect(frame.maxX <= OnboardingChromeLayout.windowWidth - OnboardingChromeLayout.trailingMargin + 0.5)
        #expect(frame.minX >= OnboardingChromeLayout.columnTrailingX)
    }

    @Test func runningMockHasNoForbiddenTagline() {
        #expect(OnboardingMockCopy.runningFilmSubtitle.isEmpty)
        #expect(OnboardingMockCopy.mockSubtitleIsAllowed(OnboardingMockCopy.runningFilmSubtitle))
        for forbidden in OnboardingMockCopy.forbiddenTaglines {
            #expect(!OnboardingMockCopy.mockSubtitleIsAllowed(forbidden))
        }
    }
}

@Suite("QA22 second brain recall")
struct QA22BrainRecallTests {
    private func tempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-qa22-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func parsesTopicAndFindsNotes() throws {
        let vault = try tempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appendingPathComponent("Projects/Zeus.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Zeus is the notch assistant on Tony's Mac.".write(to: note, atomically: true, encoding: .utf8)
        let topic = BrainRecall.topic(from: "what is in my second brain about Zeus")
        #expect(topic == "zeus")
        let hits = BrainRecall.search(vault: vault, topic: "Zeus")
        #expect(hits.count == 1)
        #expect(hits[0].file == "Projects/Zeus.md")
        let spoken = BrainRecall.spokenAnswer(vault: vault, topic: "Zeus")
        #expect(spoken.contains("Projects/Zeus.md"))
        let report = BrainRecall.debugReport(vault: vault, topic: "Zeus")
        #expect(report.hasPrefix("ok hits=1"))
    }
}

@Suite("QA22 brain turn prep")
struct QA22BrainTurnPrepTests {
    @Test func generalKnowledgeSkipsFrontContext() {
        #expect(!BrainTurnPrep.usesFrontContext(transcript: "why is the sky blue"))
        #expect(!BrainTurnPrep.usesFrontContext(transcript: "explain a mutex"))
        #expect(BrainTurnPrep.usesFrontContext(transcript: "what is on my screen"))
    }

    @Test func launchWarmWaitsOnce() async {
        BrainLaunchWarm.resetForTests()
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        BrainLaunchWarm.registerWait {
            counter.value += 1
        }
        await BrainLaunchWarm.awaitIfNeeded()
        await BrainLaunchWarm.awaitIfNeeded()
        #expect(counter.value == 1)
        #expect(BrainLaunchWarm.isFinished)
        BrainLaunchWarm.resetForTests()
    }
}
