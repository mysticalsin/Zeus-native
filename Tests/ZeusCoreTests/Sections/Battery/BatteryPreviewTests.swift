import Foundation
import Testing
import ZeusCore

@Suite("Battery live preview")
struct BatteryPreviewTests {
    private let preferences = BatteryPreferences.standard

    @Test func thePreviewIsARingAndEarbudsAreUnknownWhileTheSettingIsOff() {
        let model = BatteryPreview.make(
            observation: .battery(BatteryPowerSample(percent: 42, charging: true, onAC: true)),
            preferences: preferences,
            earbud: hostileReport(),
            reduceMotion: false
        )
        #expect(model.load == .ready)
        #expect(model.ringFraction == 0.42)
        #expect(model.charging)
        #expect(model.style == .gauge)
        #expect(model.earbuds.map(\.text) == ["unknown", "unknown", "unknown"])
        #expect(model.earbuds.map(\.title) == ["Left", "Right", "Case"])
        #expect(model.modeLabel == nil)
        #expect(model.ringLabel == "Battery 42 percent, charging")
        for part in model.earbuds {
            #expect(part.text != "0%")
            #expect(part.accessibilityLabel.contains("unknown"))
        }
    }

    @Test func turningEarbudsOnUsesTheReportAndStillRefusesZero() {
        var report = EarbudStatusReport(
            levels: [.left: .fresh(80), .right: .unknown, .cradle: .lastKnown(60), .single: .fresh(0)],
            visibleParts: [.left, .right, .cradle],
            mode: .shown(current: .noiseCancelling, choices: [
                ListeningModeChoice(mode: .off, state: .available),
                ListeningModeChoice(mode: .noiseCancelling, state: .selected),
            ]),
            consultedPrivateKeys: true,
            accessibilitySummary: "Left 80 percent. Right unknown. Case 60 percent."
        )
        report.levels[.left] = .fresh(80)
        let model = BatteryPreview.make(
            observation: .battery(BatteryPowerSample(percent: 10, charging: false, onAC: false)),
            preferences: BatteryPreferences(lightsEnabled: true, style: .ring, earbudsEnabled: true),
            earbud: report,
            reduceMotion: true
        )
        #expect(model.earbuds.map(\.text) == ["80%", "unknown", "60%"])
        #expect(model.modeLabel == "Noise cancelling")
        #expect(model.animationDuration == 0)
        #expect(model.style == .ring)
        #expect(!model.earbuds.contains(where: { $0.text == "0%" }))
        #expect(model.ringLabel == "Battery 10 percent, on battery")
    }

    @Test func loadingEmptyAndErrorAreDistinct() {
        let loading = BatteryPreview.make(observation: .loading, preferences: preferences, earbud: nil, reduceMotion: false)
        #expect(loading.load == .loading)
        #expect(loading.ringFraction == nil)
        #expect(loading.ringLabel == BatterySectionCopy.loadingLabel)
        let empty = BatteryPreview.make(observation: .noBattery, preferences: preferences, earbud: nil, reduceMotion: false)
        #expect(empty.load == .empty)
        #expect(empty.ringFraction == nil)
        #expect(empty.ringLabel == BatterySectionCopy.emptyTitle)
        let failed = BatteryPreview.make(observation: .failed, preferences: preferences, earbud: nil, reduceMotion: false)
        #expect(failed.load == .failed(BatterySectionCopy.errorTitle))
        #expect(failed.ringLabel == BatterySectionCopy.errorTitle)
        #expect(failed.ringFraction == nil)
    }

    @Test func ringFractionTracksThePercentAndNeverInventsOne() {
        for percent in 0...100 {
            let model = BatteryPreview.make(
                observation: .battery(BatteryPowerSample(percent: percent, charging: false, onAC: false)),
                preferences: preferences,
                earbud: nil,
                reduceMotion: false
            )
            #expect(model.ringFraction == Double(percent) / 100)
        }
        for percent in [nil, -1, 101] {
            let model = BatteryPreview.make(
                observation: .battery(BatteryPowerSample(percent: percent, charging: false, onAC: false)),
                preferences: preferences,
                earbud: nil,
                reduceMotion: false
            )
            #expect(model.load == .failed(BatterySectionCopy.errorTitle))
            #expect(model.ringFraction == nil)
        }
    }

    @Test func everyControlHasAHelperAndAVoiceOverLabel() {
        #expect(BatterySectionCopy.controls.count >= 3)
        var ids: [String] = []
        for control in BatterySectionCopy.controls {
            #expect(!control.title.isEmpty)
            #expect(!control.helper.isEmpty)
            #expect(!control.accessibilityLabel.isEmpty)
            #expect(!control.helper.contains("—"))
            #expect(!control.helper.contains("–"))
            #expect(!control.title.contains("—"))
            ids.append(control.id)
        }
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(BatteryLightsSetting.key))
        #expect(ids.contains(BatteryEarbudSetting.key))
        #expect(ids.contains(BatteryOverlayStyle.storageKey))
        #expect(!BatterySectionCopy.previewHelper.isEmpty)
        #expect(BatterySectionAccessibility.focusOrder == ids + ["battery.preview"])
    }

    @Test func metricsMatchTheGlassShell() {
        #expect(BatterySectionMetrics.rowHeight == 52)
        #expect(BatterySectionMetrics.panelPadding == 32)
        #expect(BatterySectionMetrics.cardGap == 28)
        #expect(BatterySectionPlacement.topbarTab == 3)
    }

    @Test func reduceMotionCoversEveryPreviewStyle() {
        for style in BatteryOverlayStyle.allCases {
            for motion in [false, true] {
                let model = BatteryPreview.make(
                    observation: .battery(BatteryPowerSample(percent: 70, charging: false, onAC: true)),
                    preferences: BatteryPreferences(lightsEnabled: true, style: style, earbudsEnabled: false),
                    earbud: nil,
                    reduceMotion: motion
                )
                #expect(model.animationDuration == BatteryMotion.duration(reduceMotion: motion, style: style))
                #expect(model.reduceMotion == motion)
            }
        }
    }

    @Test func theBatterySectionDoesNotNameAnotherProduct() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let folders = [
            root.appendingPathComponent("Sources/ZeusCore/Settings/Sections/Battery"),
            root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/Battery"),
            root.appendingPathComponent("Tests/ZeusCoreTests/Sections/Battery"),
        ]
        let banned = ["AirPods", "AirPod", "Boring Notch", "BoringNotch"]
        var hits: [String] = []
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for word in banned where text.contains(word) {
                    hits.append("\(url.lastPathComponent):\(word)")
                }
            }
        }
        #expect(hits.isEmpty)
    }

    private func hostileReport() -> EarbudStatusReport {
        EarbudStatusReport(
            levels: [.left: .fresh(0), .right: .fresh(0), .cradle: .fresh(0)],
            visibleParts: [.left, .right, .cradle],
            mode: .shown(current: .off, choices: []),
            consultedPrivateKeys: true,
            accessibilitySummary: "0%"
        )
    }
}
