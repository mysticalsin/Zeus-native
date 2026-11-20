import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("General settings")
struct GeneralSettingsTests {
    @Test func windowAppearanceResolvesTheThreeFinishesAndLegacyValues() {
        #expect(GeneralWindowAppearance.resolve(nil) == .dark)
        #expect(GeneralWindowAppearance.resolve("") == .dark)
        #expect(GeneralWindowAppearance.resolve("System") == .dark)
        #expect(GeneralWindowAppearance.resolve("Light") == .dark)
        #expect(GeneralWindowAppearance.resolve("dark") == .dark)
        #expect(GeneralWindowAppearance.resolve("GLASS") == .dark)
        #expect(GeneralWindowAppearance.resolve("Dark") == .dark)
        #expect(GeneralWindowAppearance.resolve("Glass") == .glass)
        #expect(GeneralWindowAppearance.resolve("Clear glass") == .clearGlass)
        for appearance in GeneralWindowAppearance.allCases {
            #expect(GeneralWindowAppearance.resolve(appearance.rawValue) == appearance)
        }
        #expect(GeneralWindowAppearance.key == "general.windowTheme")
    }

    @Test func windowPreviewStaysInsideOpacityAndRespectsReduceMotion() {
        let blurSamples = [0.0, 40.0, 50.0, 100.0, -10.0, 140.0, Double.nan]
        for appearance in GeneralWindowAppearance.allCases {
            for blur in blurSamples {
                for motion in [false, true] {
                    for transparency in [false, true] {
                        let preview = appearance.preview(blur: blur, reduceMotion: motion, reduceTransparency: transparency)
                        #expect(preview.appearance == appearance)
                        #expect(preview.fillOpacity >= 0 && preview.fillOpacity <= 1)
                        #expect(preview.blurRadius >= 0)
                        #expect(preview.animationDuration >= 0)
                        #expect(!preview.accessibilityLabel.isEmpty)
                        if motion {
                            #expect(preview.animationDuration == 0)
                        } else {
                            #expect(preview.animationDuration == MotionTokens.crossfadeDuration)
                        }
                        if appearance == .dark || transparency {
                            #expect(preview.solid)
                            #expect(preview.fillOpacity == 1)
                            #expect(preview.blurRadius == 0)
                        }
                    }
                }
            }
        }
        let glass = GeneralWindowAppearance.glass.preview(blur: 50, reduceMotion: false, reduceTransparency: false)
        #expect(glass.solid == false)
        #expect(glass.fillOpacity == 0.72)
        #expect(glass.blurRadius == 16)
        let clear = GeneralWindowAppearance.clearGlass.preview(blur: 0, reduceMotion: false, reduceTransparency: false)
        #expect(clear.solid == false)
        #expect(clear.fillOpacity == 0.38)
        #expect(clear.blurRadius == 0)
        let full = GeneralWindowAppearance.glass.preview(blur: 100, reduceMotion: true, reduceTransparency: false)
        #expect(full.blurRadius == 32)
        #expect(full.animationDuration == 0)
        #expect(glass.accessibilityLabel == "Window appearance preview, Glass")
    }

    @Test func blurStrengthClampsToTheClosedRangeOnItsStep() {
        #expect(GeneralBlurStrength.key == "general.backgroundBlur")
        #expect(GeneralBlurStrength.minimum == 0)
        #expect(GeneralBlurStrength.maximum == 100)
        #expect(GeneralBlurStrength.step == 1)
        #expect(GeneralBlurStrength.defaultValue == 40)
        #expect(GeneralBlurStrength.parse(nil) == 40)
        #expect(GeneralBlurStrength.parse("") == 40)
        #expect(GeneralBlurStrength.parse("nope") == 40)
        #expect(GeneralBlurStrength.parse("0") == 0)
        #expect(GeneralBlurStrength.parse("100") == 100)
        #expect(GeneralBlurStrength.parse("40.4") == 40)
        #expect(GeneralBlurStrength.parse("40.5") == 41)
        #expect(GeneralBlurStrength.parse("100.4") == 100)
        #expect(GeneralBlurStrength.parse("100.5") == 100)
        #expect(GeneralBlurStrength.parse("-0.4") == 0)
        #expect(GeneralBlurStrength.parse("-0.5") == 0)
        #expect(GeneralBlurStrength.clamp(.nan) == 40)
        #expect(GeneralBlurStrength.clamp(.infinity) == 40)
        #expect(GeneralBlurStrength.clamp(-.infinity) == 40)
        #expect(GeneralBlurStrength.clamp(1e308) == 100)
        #expect(GeneralBlurStrength.clamp(-1e308) == 0)
        for value in 0...100 {
            let number = Double(value)
            #expect(GeneralBlurStrength.clamp(number) == number)
            #expect(GeneralBlurStrength.parse(String(number)) == number)
        }
        var previous = GeneralBlurStrength.clamp(-20)
        for value in stride(from: -20.0, through: 120.0, by: 0.5) {
            let next = GeneralBlurStrength.clamp(value)
            #expect(next >= GeneralBlurStrength.minimum && next <= GeneralBlurStrength.maximum)
            #expect(next >= previous)
            #expect(next == GeneralBlurStrength.parse(String(next)))
            previous = next
        }
    }

    @Test func twoDisplaysFollowTheStoredNotchMode() {
        let screens = twoDisplays()
        let swapped = [screens[1], screens[0]]
        #expect(GeneralNotchScreens.mode(nil) == .builtIn)
        #expect(GeneralNotchScreens.mode("Built-in display") == .builtIn)
        #expect(GeneralNotchScreens.mode("Display with the pointer") == .pointer)
        #expect(GeneralNotchScreens.mode("All displays") == .all)
        #expect(GeneralNotchScreens.mode("nope") == .builtIn)
        let onExternal = CGPoint(x: 1700, y: 200)
        let onBuiltIn = CGPoint(x: 80, y: 80)
        let nowhere = CGPoint(x: -40, y: -40)
        #expect(readyIDs(.builtIn, screens, onExternal) == [1])
        #expect(readyIDs(.builtIn, swapped, onExternal) == [1])
        #expect(readyIDs(.pointer, screens, onExternal) == [2])
        #expect(readyIDs(.pointer, screens, onBuiltIn) == [1])
        #expect(readyIDs(.pointer, screens, nowhere) == [1])
        #expect(readyIDs(.all, screens, nowhere) == [1, 2])
        #expect(readyIDs(.all, swapped, onExternal) == [1, 2])
        #expect(GeneralNotchScreens.readout(loaded: false, screens: screens, pointer: onExternal, mode: .all, failure: nil) == .loading)
        #expect(GeneralNotchScreens.readout(loaded: true, screens: [], pointer: onExternal, mode: .all, failure: nil) == .empty)
        #expect(GeneralNotchScreens.readout(loaded: false, screens: [], pointer: .zero, mode: .builtIn, failure: "  ") == .failed("Displays could not be read."))
        #expect(GeneralNotchScreens.readout(loaded: true, screens: screens, pointer: onExternal, mode: .all, failure: "Cable") == .failed("Cable"))
    }

    @Test func fullScreenHidingAndScreenCaptureStayIndependent() {
        #expect(GeneralFullScreenHiding.key == "general.hideInFullScreen")
        #expect(GeneralFullScreenHiding.enabled(nil) == false)
        #expect(GeneralFullScreenHiding.enabled("true") == true)
        #expect(GeneralFullScreenHiding.enabled("false") == false)
        #expect(GeneralFullScreenHiding.enabled("TRUE") == false)
        for hide in [false, true] {
            for fullScreen in [false, true] {
                let visible = GeneralFullScreenHiding.notchVisible(hideWhenFullScreen: hide, frontmostIsFullScreen: fullScreen)
                #expect(visible == !(hide && fullScreen))
            }
        }
        #expect(GeneralScreenCapture.key == "general.showInScreenSharing")
        #expect(GeneralScreenCapture.enabled(nil) == false)
        #expect(GeneralScreenCapture.enabled("true") == true)
        #expect(GeneralScreenCapture.enabled("false") == false)
        #expect(GeneralScreenCapture.surfacesVisible(showInScreenSharing: false, meetingActive: true, teleprompterSessionHidden: false) == false)
        #expect(GeneralScreenCapture.surfacesVisible(showInScreenSharing: true, meetingActive: true, teleprompterSessionHidden: false) == true)
        #expect(GeneralScreenCapture.surfacesVisible(showInScreenSharing: true, meetingActive: false, teleprompterSessionHidden: true) == false)
        let input = sampleInput(values: ["general.hideInFullScreen": "true", "general.showInScreenSharing": "true", "notch.displays": "All displays"], fullScreen: true)
        let output = GeneralSettingsResolver.resolve(input)
        #expect(output.notchVisible == false)
        if case .ready(let ids) = output.displays { #expect(ids == [1, 2]) } else { Issue.record("two displays were not ready") }
        #expect(output.visibleInScreenCapture == true)
    }

    @Test func menuBarLaunchSetupAndHapticsUseTheExistingRules() {
        #expect(GeneralMenuBarIcon.key == "showMenuBarIcon")
        #expect(GeneralMenuBarIcon.shown(nil) == true)
        #expect(GeneralMenuBarIcon.shown(true) == true)
        #expect(GeneralMenuBarIcon.shown(false) == false)
        #expect(GeneralMenuBarIcon.helper(shown: true) == "Shows Zeus in the menu bar.")
        #expect(GeneralMenuBarIcon.helper(shown: false) == "To get back here, open Zeus again from Applications or Spotlight.")
        #expect(GeneralLaunchAtLogin.key == "general.launchAtLogin")
        #expect(GeneralLaunchAtLogin.enabled(nil) == true)
        #expect(GeneralLaunchAtLogin.enabled("true") == true)
        #expect(GeneralLaunchAtLogin.enabled("false") == false)
        #expect(GeneralLaunchAtLogin.enabled("TRUE") == false)
        #expect(GeneralLaunchAtLogin.enabled("") == false)
        #expect(GeneralSetupReplay.key == "general.runSetup")
        var setup = GeneralSetupReplay.idle
        setup = GeneralSetupReplay.transition(setup, .start)
        #expect(setup == .running)
        #expect(GeneralSetupReplay.transition(setup, .start) == .running)
        #expect(GeneralSetupReplay.transition(setup, .finished) == .idle)
        #expect(GeneralSetupReplay.transition(.running, .failed("  ")) == .failed("The setup guide could not open."))
        #expect(GeneralSetupReplay.transition(.failed("Busy"), .dismiss) == .idle)
        #expect(GeneralSetupReplay.transition(.failed("Busy"), .start) == .running)
        #expect(GeneralSetupReplay.transition(.idle, .finished) == .idle)
        #expect(GeneralHaptics.key == "general.hapticFeedback")
        #expect(GeneralHaptics.enabled(nil) == false)
        #expect(GeneralHaptics.enabled("true") == true)
        #expect(GeneralHaptics.readout(loaded: false, storedOn: true, forceTouch: true, failure: nil) == .loading)
        #expect(GeneralHaptics.readout(loaded: true, storedOn: false, forceTouch: true, failure: "x") == .off)
        #expect(GeneralHaptics.readout(loaded: true, storedOn: true, forceTouch: false, failure: nil) == .unavailable)
        #expect(GeneralHaptics.readout(loaded: true, storedOn: true, forceTouch: true, failure: nil) == .on)
        #expect(GeneralHaptics.readout(loaded: true, storedOn: true, forceTouch: true, failure: " ") == .failed("Haptic feedback is unavailable."))
        for readout in [GeneralHapticReadout.loading, .off, .unavailable, .failed("x"), .on] {
            #expect(GeneralHaptics.plays(readout) == (readout == .on))
        }
    }

    @Test func drawnShapeLinksToAppearanceWithoutItsOwnSliders() {
        #expect(GeneralDrawnShapeLink.widthKey == "notch.drawnWidth")
        #expect(GeneralDrawnShapeLink.heightKey == "notch.drawnHeight")
        #expect(GeneralDrawnShapeLink.destinationID == "appearance")
        let linked = GeneralSettingsSectionModel.controls.filter { $0.kind == .link }
        #expect(linked.count == 1)
        #expect(linked[0].keys == ["notch.drawnWidth", "notch.drawnHeight"])
        #expect(linked[0].placement == .link("appearance"))
        #expect(linked[0].title == GeneralDrawnShapeLink.title)
        #expect(!GeneralSettingsSectionModel.controls.contains { $0.kind == .slider && $0.keys.contains("notch.drawnWidth") })
        #expect(!GeneralSettingsSectionModel.controls.contains { $0.kind == .slider && $0.keys.contains("notch.drawnHeight") })
    }

    @Test func sectionKeepsExistingGeneralRowsAndAddsTheMissingOnesBelow() {
        #expect(GeneralSettingsSectionModel.placementSection == "general")
        #expect(GeneralSettingsSectionModel.placementOrder == 1)
        #expect(GeneralSettingsSectionModel.previewControlID == "settings.general.windowTheme")
        #expect(GeneralSectionSlot.descriptor.filled == false)
        #expect(GeneralSectionSlot.descriptor.keys.isEmpty)
        #expect(GeneralSettingsLayout.rowHeight == 52)
        #expect(GeneralSettingsLayout.panelPadding == 32)
        #expect(GeneralSettingsLayout.cardSpacing == 28)
        #expect(GeneralSettingsSectionModel.controls.map(\.id) == expectedControls.map(\.id))
        #expect(GeneralSettingsSectionModel.controls == expectedControls)
        let labels = GeneralSettingsSectionModel.controls.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
        for control in GeneralSettingsSectionModel.controls {
            #expect(!control.id.isEmpty)
            #expect(!control.title.isEmpty)
            #expect(!control.helper.isEmpty)
            #expect(!control.accessibilityLabel.isEmpty)
        }
        let existing = GeneralSettingsSectionModel.controls.filter { $0.placement == .existingPage }.flatMap(\.keys)
        #expect(existing == ["notch.displays", "general.showInScreenSharing", "general.launchAtLogin", "general.runSetup"])
        let cardOrders = GeneralSettingsSectionModel.controls.compactMap { control -> Int? in
            if case .card(let order) = control.placement { return order }
            return nil
        }
        #expect(cardOrders == [1, 2, 3, 4, 5, 6])
    }

    @Test func bannersExposeLoadingEmptyAndError() {
        #expect(GeneralSettingsSectionModel.banner(displays: .loading, haptics: .off) == .loading("Loading settings…"))
        #expect(GeneralSettingsSectionModel.banner(displays: .ready([1]), haptics: .loading) == .loading("Loading settings…"))
        #expect(GeneralSettingsSectionModel.banner(displays: .empty, haptics: .off) == .empty("No display is connected."))
        #expect(GeneralSettingsSectionModel.banner(displays: .failed("Cable"), haptics: .loading) == .error("Cable"))
        #expect(GeneralSettingsSectionModel.banner(displays: .ready([1]), haptics: .failed("Trackpad")) == .error("Trackpad"))
        #expect(GeneralSettingsSectionModel.banner(displays: .ready([1, 2]), haptics: .on) == nil)
        #expect(GeneralSettingsSectionModel.banner(displays: .empty, haptics: .unavailable) == .empty("No display is connected."))
    }

    @Test func resolverReadsTheWholeSectionFromOneSnapshot() {
        var input = sampleInput(values: [
            "general.windowTheme": "Clear glass",
            "general.backgroundBlur": "25.4",
            "notch.displays": "Display with the pointer",
            "general.hideInFullScreen": "false",
            "general.showInScreenSharing": "false",
            "general.hapticFeedback": "true",
            "general.launchAtLogin": "false",
        ], fullScreen: true)
        input.menuBarStored = false
        input.pointer = CGPoint(x: 1700, y: 40)
        input.forceTouch = true
        input.reduceMotion = true
        let output = GeneralSettingsResolver.resolve(input)
        #expect(output.appearance == .clearGlass)
        #expect(output.preview.solid == false)
        #expect(output.preview.blurRadius == 8)
        #expect(output.preview.animationDuration == 0)
        #expect(output.blur == 25)
        #expect(output.displays == .ready([2]))
        #expect(output.notchVisible == true)
        #expect(output.visibleInScreenCapture == false)
        #expect(output.menuBarShown == false)
        #expect(output.haptics == .on)
        #expect(output.hapticsPlay == true)
        #expect(output.launchAtLogin == false)
        #expect(output.banner == nil)
        input.forceTouch = false
        #expect(GeneralSettingsResolver.resolve(input).haptics == .unavailable)
        #expect(GeneralSettingsResolver.resolve(input).hapticsPlay == false)
    }

    @Test func resetKeepsTheLoginItemAndTheLicense() {
        let values = [
            "general.launchAtLogin": "false",
            "opt.general.launchAtLogin": "false",
            "license": "AB",
            "license.server": "https://licenses.example.com",
            "license.key": "secret",
            "license.activation": "token",
            "opt.license.revocations": "1",
            "general.windowTheme": "Glass",
            "general.backgroundBlur": "80",
            "showMenuBarIcon": "false",
            "notch.displays": "All displays",
            "custom.extra": "drop",
        ]
        let defaults = [
            "general.launchAtLogin": "true",
            "license.server": "https://default.example",
            "license.revocations": "",
            "general.windowTheme": "Dark",
            "general.backgroundBlur": "40",
            "showMenuBarIcon": "true",
            "notch.displays": "Built-in display",
        ]
        let next = GeneralSettingsReset.applying(values: values, defaults: defaults)
        #expect(next["general.launchAtLogin"] == "false")
        #expect(next["opt.general.launchAtLogin"] == "false")
        #expect(next["license"] == "AB")
        #expect(next["license.server"] == "https://licenses.example.com")
        #expect(next["license.key"] == "secret")
        #expect(next["license.activation"] == "token")
        #expect(next["opt.license.revocations"] == "1")
        #expect(next["license.revocations"] == "")
        #expect(next["general.windowTheme"] == "Dark")
        #expect(next["general.backgroundBlur"] == "40")
        #expect(next["showMenuBarIcon"] == "true")
        #expect(next["notch.displays"] == "Built-in display")
        #expect(next["custom.extra"] == nil)
        let long = String(repeating: "k", count: 20_000)
        let preserved = GeneralSettingsReset.applying(values: ["license.key": long + "\n"], defaults: ["license.key": ""])
        #expect(preserved["license.key"] == long + "\n")
    }

    @Test func resetIsPureAndPreservesOnlyLoginAndLicenseKeys() {
        let keys = [
            "general.launchAtLogin", "opt.general.launchAtLogin", "license", "license.server", "license.key",
            "opt.license.activation", "general.windowTheme", "showMenuBarIcon", "licenses", "licensee", "",
        ]
        let sample = ["false", "true", "Dark", "Glass", "", "x"]
        for mask in 0..<(1 << keys.count) {
            var values: [String: String] = [:]
            var defaults: [String: String] = [:]
            for (index, key) in keys.enumerated() {
                if mask & (1 << index) != 0 { values[key] = sample[index % sample.count] }
                if index % 2 == 0 { defaults[key] = "default-\(index)" }
            }
            let beforeValues = values
            let beforeDefaults = defaults
            let next = GeneralSettingsReset.applying(values: values, defaults: defaults)
            #expect(values == beforeValues)
            #expect(defaults == beforeDefaults)
            #expect(next == GeneralSettingsReset.applying(values: next, defaults: defaults))
            for key in Set(values.keys).union(defaults.keys) {
                if GeneralSettingsReset.preserves(key) {
                    #expect(next[key] == (values[key] ?? defaults[key]))
                } else if let fallback = defaults[key] {
                    #expect(next[key] == fallback)
                } else {
                    #expect(next[key] == nil)
                }
            }
            for key in next.keys {
                #expect(values[key] != nil || defaults[key] != nil)
                let bare = key.hasPrefix("opt.") ? String(key.dropFirst(4)) : key
                if next[key] != defaults[key] {
                    #expect(bare == "general.launchAtLogin" || bare == "license" || bare.hasPrefix("license."))
                }
            }
        }
        #expect(GeneralSettingsReset.preserves("License.server") == false)
        #expect(GeneralSettingsReset.preserves("opt.") == false)
        #expect(GeneralSettingsReset.preserves("general.launchAtLogin.extra") == false)
    }

    @Test func resetConfirmationTakesTwoStepsAndGuardsEveryOtherEvent() {
        var state = GeneralResetConfirmation.idle
        state = GeneralResetConfirmation.transition(state, .commit)
        #expect(state == .idle)
        state = GeneralResetConfirmation.transition(state, .advance)
        #expect(state == .idle)
        state = GeneralResetConfirmation.transition(state, .ask)
        #expect(state == .review)
        state = GeneralResetConfirmation.transition(state, .commit)
        #expect(state == .review)
        state = GeneralResetConfirmation.transition(state, .advance)
        #expect(state == .commit)
        state = GeneralResetConfirmation.transition(state, .cancel)
        #expect(state == .idle)
        state = GeneralResetConfirmation.transition(state, .ask)
        state = GeneralResetConfirmation.transition(state, .advance)
        state = GeneralResetConfirmation.transition(state, .commit)
        #expect(state == .applying)
        #expect(GeneralResetConfirmation.transition(state, .cancel) == .applying)
        #expect(GeneralResetConfirmation.transition(state, .failed(" ")) == .failed("Settings could not be reset."))
        #expect(GeneralResetConfirmation.transition(.failed("Disk"), .ask) == .review)
        #expect(GeneralResetConfirmation.transition(.failed("Disk"), .dismiss) == .idle)
        #expect(GeneralResetConfirmation.transition(.applying, .succeeded) == .finished)
        #expect(GeneralResetConfirmation.transition(.finished, .dismiss) == .idle)

        let states: [GeneralResetConfirmation] = [.idle, .review, .commit, .applying, .failed("disk"), .finished]
        let events: [GeneralResetConfirmation.Event] = [.ask, .advance, .commit, .cancel, .succeeded, .failed("nope"), .failed(""), .dismiss]
        for current in states {
            for event in events {
                let next = GeneralResetConfirmation.transition(current, event)
                if next == .applying, current != .applying {
                    #expect(current == .commit)
                    #expect(event == .commit)
                }
                if next == .finished, current != .finished {
                    #expect(current == .applying)
                    #expect(event == .succeeded)
                }
                if case .failed = next, next != current {
                    #expect(current == .applying)
                    if case .failed = event {} else { #expect(Bool(false)) }
                }
            }
        }
        #expect(GeneralResetConfirmation.chrome(.idle).primaryTitle == "Reset all settings")
        #expect(GeneralResetConfirmation.chrome(.review).primaryTitle == "Continue")
        #expect(GeneralResetConfirmation.chrome(.review).secondaryTitle == "Cancel")
        #expect(GeneralResetConfirmation.chrome(.commit).primaryTitle == "Reset now")
        #expect(GeneralResetConfirmation.chrome(.commit).secondaryTitle == "Cancel")
        #expect(GeneralResetConfirmation.chrome(.applying).showsProgress)
        #expect(GeneralResetConfirmation.chrome(.applying).primaryTitle == nil)
        let failed = GeneralResetConfirmation.chrome(.failed("Disk"))
        #expect(failed.isError)
        #expect(failed.helper == "Disk")
        #expect(failed.primaryTitle == "Try again")
        #expect(failed.secondaryTitle == "Dismiss")
        let finished = GeneralResetConfirmation.chrome(.finished)
        #expect(finished.helper == "Launch at login and the license are unchanged.")
        #expect(finished.primaryTitle == "Done")
        for sample in states {
            let chrome = GeneralResetConfirmation.chrome(sample)
            #expect(!chrome.title.isEmpty)
            #expect(!chrome.helper.isEmpty)
            #expect(!chrome.accessibilityLabel.isEmpty)
        }
    }

    private func readyIDs(_ mode: NotchDisplayMode, _ screens: [DisplayDescriptor], _ pointer: CGPoint) -> [Int] {
        guard case .ready(let ids) = GeneralNotchScreens.readout(loaded: true, screens: screens, pointer: pointer, mode: mode, failure: nil) else {
            return []
        }
        return ids
    }

    private func twoDisplays() -> [DisplayDescriptor] {
        [
            DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), hasNotch: true, isBuiltIn: true),
            DisplayDescriptor(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), hasNotch: false, isBuiltIn: false),
        ]
    }

    private func sampleInput(values: [String: String], fullScreen: Bool) -> GeneralSettingsInput {
        GeneralSettingsInput(
            values: values,
            menuBarStored: true,
            displaysLoaded: true,
            displays: twoDisplays(),
            pointer: CGPoint(x: 80, y: 80),
            displayFailure: nil,
            frontmostIsFullScreen: fullScreen,
            meetingActive: true,
            teleprompterSessionHidden: false,
            hapticsLoaded: true,
            forceTouch: false,
            hapticFailure: nil,
            reduceMotion: false,
            reduceTransparency: false
        )
    }
}

private let expectedControls: [GeneralControlSpec] = [
    GeneralControlSpec(id: "settings.general.windowTheme", keys: ["general.windowTheme"], title: "Window appearance", helper: "Dark, glass, or clear glass for Settings.", accessibilityLabel: "Window appearance", kind: .choice, placement: .card(1)),
    GeneralControlSpec(id: "settings.general.backgroundBlur", keys: ["general.backgroundBlur"], title: "Background blur", helper: "0 is no blur and 100 is the strongest.", accessibilityLabel: "Background blur strength", kind: .slider, placement: .card(2)),
    GeneralControlSpec(id: "settings.general.notchDisplays", keys: ["notch.displays"], title: "Show the notch on", helper: "Which screens carry the notch.", accessibilityLabel: "Show the notch on", kind: .choice, placement: .existingPage),
    GeneralControlSpec(id: "settings.general.hideInFullScreen", keys: ["general.hideInFullScreen"], title: "Hide in full-screen apps", helper: "Hides the notch while the front app is full screen.", accessibilityLabel: "Hide in full-screen apps", kind: .toggle, placement: .card(3)),
    GeneralControlSpec(id: "settings.general.showInScreenSharing", keys: ["general.showInScreenSharing"], title: "Show in screen sharing", helper: "Off keeps Zeus windows out of screen shares and recordings.", accessibilityLabel: "Show in screen sharing", kind: .toggle, placement: .existingPage),
    GeneralControlSpec(id: "settings.general.menuBarIcon", keys: ["showMenuBarIcon"], title: "Menu bar icon", helper: "Shows Zeus in the menu bar.", accessibilityLabel: "Menu bar icon", kind: .toggle, placement: .card(4)),
    GeneralControlSpec(id: "settings.general.drawnShape", keys: ["notch.drawnWidth", "notch.drawnHeight"], title: "Fit the drawn shape to the notch", helper: "Width and height stay on Appearance.", accessibilityLabel: "Fit the drawn shape to the notch, set in Appearance", kind: .link, placement: .link("appearance")),
    GeneralControlSpec(id: "settings.general.hapticFeedback", keys: ["general.hapticFeedback"], title: "Haptic feedback", helper: "Uses the Force Touch trackpad. Stays off when this Mac has none.", accessibilityLabel: "Haptic feedback", kind: .toggle, placement: .card(5)),
    GeneralControlSpec(id: "settings.general.launchAtLogin", keys: ["general.launchAtLogin"], title: "Launch at login", helper: "Starts Zeus when you log in.", accessibilityLabel: "Launch at login", kind: .toggle, placement: .existingPage),
    GeneralControlSpec(id: "settings.general.runSetup", keys: ["general.runSetup"], title: "Run setup again", helper: "Replays the first-run guide.", accessibilityLabel: "Run setup again", kind: .action, placement: .existingPage),
    GeneralControlSpec(id: "settings.general.reset", keys: [], title: "Reset all settings", helper: "Puts every setting back. Launch at login and the license stay.", accessibilityLabel: "Reset all settings", kind: .action, placement: .card(6)),
]
