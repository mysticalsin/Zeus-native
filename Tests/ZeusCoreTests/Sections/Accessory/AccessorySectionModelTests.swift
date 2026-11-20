import Foundation
import Testing
import ZeusCore

@Suite("Accessory section")
struct AccessorySectionModelTests {
    @Test func theSectionStartsClosed() {
        let model = AccessorySectionModel()
        #expect(model.preferences == .failClosed)
        #expect(model.overlay.phase == .closed)
        #expect(model.speakers.phase == .off)
        #expect(model.confirmation == .idle)
        #expect(model.reduceMotion == false)
        #expect(model.preview.visible == false)
        let controls = AccessorySectionSurface.controls(model)
        #expect(controls.map(\.id) == ["earbuds", "style", "speakers", "preview"])
        for control in controls {
            #expect(control.keyboardReachable)
            #expect(!control.accessibilityLabel.isEmpty)
            #expect(!control.accessibilityHint.isEmpty)
        }
    }

    @Test func speakerNamesDoNotBrowseUntilLocalNetworkIsOn() {
        var model = AccessorySectionModel()
        let kitchen = [NearbySpeaker(id: "kitchen", name: "Kitchen")]
        #expect(model.handle(.speakersFound(kitchen)).isEmpty)
        #expect(model.speakers.phase == .off)

        #expect(model.handle(.askToEnableSpeakers).isEmpty)
        #expect(model.confirmation == .enableSpeakers)
        #expect(model.preferences.speakerNames == false)
        #expect(model.handle(.speakersFound(kitchen)).isEmpty)
        #expect(model.handle(.cancelSpeakerEnable).isEmpty)
        #expect(model.confirmation == .idle)
        #expect(model.handle(.confirmSpeakerEnable).isEmpty)
        #expect(model.speakers.phase == .off)

        #expect(model.handle(.askToEnableSpeakers).isEmpty)
        let on = AccessoryPreferences(earbudsOverlay: false, overlayStyle: .off, speakerNames: true)
        #expect(model.handle(.confirmSpeakerEnable) == [.persist(on), .requestPermission])
        #expect(model.confirmation == .idle)
        #expect(model.speakers.phase == .askingPermission)
        #expect(!model.handle(.permissionDenied).contains(.startSearch))
        #expect(model.speakers.phase == .unavailable(.denied))
        #expect(model.handle(.speakersFound(kitchen)).isEmpty)

        var allowed = AccessorySectionModel()
        _ = allowed.handle(.askToEnableSpeakers)
        _ = allowed.handle(.confirmSpeakerEnable)
        #expect(allowed.handle(.permissionAllowed) == [.startSearch])
        #expect(allowed.speakers.phase == .searching)
        #expect(allowed.handle(.speakersFound(kitchen)).isEmpty)
        #expect(allowed.speakers.phase == .names(kitchen))
        let off = allowed.handle(.disableSpeakers)
        #expect(off == [.stopSearch, .persist(.failClosed)])
        #expect(allowed.speakers.phase == .off)
        #expect(allowed.preferences.speakerNames == false)
        #expect(allowed.handle(.speakersFound(kitchen)).isEmpty)
    }

    @Test func restoringAnEnabledSpeakerSettingDoesNotBrowseOrPrompt() {
        var model = AccessorySectionModel()
        let effects = model.handle(.restore(overlay: "false", style: "off", speakers: "true"))
        #expect(effects.isEmpty)
        #expect(model.preferences.speakerNames == true)
        #expect(model.speakers.phase == .off)
        #expect(model.confirmation == .idle)
        let controls = AccessorySectionSurface.controls(model)
        #expect(controls.contains(where: { $0.id == "speakers.look" }))
        #expect(controls.allSatisfy { $0.keyboardReachable })
        #expect(model.handle(.askToEnableSpeakers).isEmpty)
        #expect(model.confirmation == .enableSpeakers)
        #expect(model.handle(.confirmSpeakerEnable) == [.requestPermission])
    }

    @Test func anImportCannotEnableTheSection() {
        var model = AccessorySectionModel()
        let imported = AccessoryPreferences(earbudsOverlay: true, overlayStyle: .split, speakerNames: true)
        #expect(model.handle(.importPreferences(imported)).isEmpty)
        #expect(model.preferences == .failClosed)
        #expect(model.overlay.phase == .closed)
        #expect(model.speakers.phase == .off)

        _ = model.handle(.setEarbudsOverlay(true))
        _ = model.handle(.setOverlayStyle(.compact))
        _ = model.handle(.askToEnableSpeakers)
        _ = model.handle(.confirmSpeakerEnable)
        _ = model.handle(.permissionAllowed)
        let closed = model.handle(.importPreferences(.failClosed))
        #expect(closed.contains(.stopSearch))
        #expect(closed.contains(.persist(.failClosed)))
        #expect(model.preferences == .failClosed)
        #expect(model.speakers.phase == .off)
        #expect(model.overlay.phase == .closed)
    }

    @Test func theConnectOverlayFollowsTheInjectedInputAndReduceMotion() {
        var model = AccessorySectionModel()
        #expect(model.handle(.earbudsConnected(AccessoryConnectInput.preview)).isEmpty)
        #expect(model.overlay.phase == .closed)
        #expect(model.handle(.setEarbudsOverlay(true)) == [.persist(AccessoryPreferences(
            earbudsOverlay: true, overlayStyle: .off, speakerNames: false
        ))])
        #expect(model.handle(.earbudsConnected(AccessoryConnectInput.preview)).isEmpty)
        #expect(model.overlay.phase == .closed)

        let styled = AccessoryPreferences(earbudsOverlay: true, overlayStyle: .compact, speakerNames: false)
        #expect(model.handle(.setOverlayStyle(.compact)) == [.persist(styled)])
        #expect(model.overlay.phase == .armed)
        #expect(model.preview.visible == true)
        #expect(model.handle(.earbudsConnected(AccessoryConnectInput.preview)) == [
            .overlay([.animateIn(MotionTokens.crossfadeDuration)]),
        ])
        #expect(model.handle(.overlayAppearFinished).isEmpty)
        guard case .visible = model.overlay.phase else {
            Issue.record("expected visible")
            return
        }
        #expect(model.handle(.overlayDismiss) == [.overlay([.animateOut(MotionTokens.crossfadeDuration)])])
        #expect(model.handle(.overlayDismissFinished).isEmpty)
        #expect(model.overlay.phase == .armed)
        #expect(model.handle(.earbudsConnected(AccessoryConnectInput.preview)).isEmpty)

        #expect(model.handle(.reduceMotion(true)).isEmpty)
        #expect(model.reduceMotion == true)
        #expect(model.preview.duration == 0)
        #expect(model.handle(.earbudsDisconnected).isEmpty)
        #expect(model.handle(.earbudsConnected(AccessoryConnectInput.preview)) == [.overlay([.showNow])])
        guard case .visible(let content) = model.overlay.phase else {
            Issue.record("expected visible")
            return
        }
        #expect(content.duration == 0)
        #expect(content.style == .compact)
    }

    @Test func loadingEmptyAndErrorStatesAreDistinctAndReachable() {
        var model = AccessorySectionModel()
        _ = model.handle(.askToEnableSpeakers)
        _ = model.handle(.confirmSpeakerEnable)
        #expect(model.speakers.phase.isLoading)
        let asking = AccessorySectionSurface.controls(model)
        #expect(asking.allSatisfy { $0.keyboardReachable })
        #expect(asking.contains(where: { $0.id == "speakers" }))

        _ = model.handle(.permissionAllowed)
        #expect(model.speakers.phase == .searching)
        _ = model.handle(.speakersFound([]))
        #expect(model.speakers.phase.isEmpty)
        #expect(!model.speakers.phase.isError)

        _ = model.handle(.searchFailed)
        #expect(model.speakers.phase.isError)
        let failed = AccessorySectionSurface.controls(model)
        #expect(failed.contains(where: { $0.id == "speakers.retry" && $0.keyboardReachable }))
        #expect(model.handle(.askToEnableSpeakers).isEmpty)
        #expect(model.confirmation == .enableSpeakers)

        var denied = AccessorySectionModel()
        _ = denied.handle(.askToEnableSpeakers)
        _ = denied.handle(.confirmSpeakerEnable)
        _ = denied.handle(.permissionDenied)
        let blocked = AccessorySectionSurface.controls(denied)
        #expect(blocked.contains(where: { $0.id == "speakers.settings" && $0.keyboardReachable }))
        #expect(denied.speakers.phase.isUnavailable)
    }

    @Test func everySurfaceControlIsLabelledAcrossThePhaseMatrix() {
        var model = AccessorySectionModel()
        var snapshots: [AccessorySectionModel] = [model]
        _ = model.handle(.setEarbudsOverlay(true))
        _ = model.handle(.setOverlayStyle(.split))
        _ = model.handle(.reduceMotion(true))
        _ = model.handle(.earbudsConnected(AccessoryConnectInput.preview))
        snapshots.append(model)
        _ = model.handle(.askToEnableSpeakers)
        snapshots.append(model)
        _ = model.handle(.confirmSpeakerEnable)
        snapshots.append(model)
        _ = model.handle(.permissionRestricted)
        snapshots.append(model)
        for snapshot in snapshots {
            let controls = AccessorySectionSurface.controls(snapshot)
            #expect(!controls.isEmpty)
            var seen: Set<String> = []
            for control in controls {
                #expect(seen.insert(control.id).inserted)
                #expect(control.keyboardReachable)
                #expect(!control.accessibilityLabel.isEmpty)
                #expect(!control.accessibilityHint.isEmpty)
                #expect(!control.accessibilityLabel.contains("—"))
            }
        }
    }

    @Test func repeatedEnablesDoNotAskTwiceAndAClosedToggleDoesNotPersist() {
        var model = AccessorySectionModel()
        #expect(model.handle(.setEarbudsOverlay(false)).isEmpty)
        #expect(model.handle(.setOverlayStyle(.off)).isEmpty)
        #expect(model.handle(.disableSpeakers).isEmpty)
        _ = model.handle(.askToEnableSpeakers)
        _ = model.handle(.confirmSpeakerEnable)
        #expect(model.handle(.askToEnableSpeakers).isEmpty)
        #expect(model.handle(.confirmSpeakerEnable).isEmpty)
        #expect(model.speakers.phase == .askingPermission)
        #expect(model.handle(.permissionAllowed) == [.startSearch])
        #expect(model.handle(.permissionAllowed).isEmpty)
    }
}
