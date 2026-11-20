import Foundation
import Testing
@testable import ZeusCore

@Suite("Portal paired devices")
struct PortalDevicesTests {
    @Test func syncStaysOffUnlessTheExistingSwitchIsOn() {
        var mixer = PortalSplitMix(state: 7)
        let flags = ["true", "false", "TRUE", "1", ""]
        for _ in 0..<64 {
            var reading = PortalFlingReading.off
            reading.enabled = "false"
            reading.receiveInBackground = flags[mixer.int(flags.count)]
            reading.visibility = ["Everyone nearby", "Paired only", "Off", "Nearby"][mixer.int(4)]
            reading.autoAcceptPaired = flags[mixer.int(flags.count)]
            reading.openLinks = flags[mixer.int(flags.count)]
            reading.papers = flags[mixer.int(flags.count)]
            reading.localNetworkDenied = mixer.int(2) == 0
            reading.peersKnown = mixer.int(2) == 0
            reading.notchOpen = mixer.int(2) == 0
            let board = PortalDeviceBoardBuilder.make(reading)
            #expect(board.phase == .off)
            #expect(!board.canSend)
            #expect(!board.canReceive)
            #expect(!board.opensLinks)
        }
        var upper = PortalFlingReading.off
        upper.enabled = "TRUE"
        #expect(PortalDeviceBoardBuilder.make(upper).phase == .off)
    }

    @Test func visibilityDenialAndTheClosedNotchFailClosed() {
        var everyone = PortalFlingReading.off
        everyone.enabled = "true"
        everyone.visibility = "Everyone nearby"
        everyone.peersKnown = true
        everyone.notchOpen = true
        everyone.receiveInBackground = "true"
        everyone.openLinks = "true"
        let open = PortalDeviceBoardBuilder.make(everyone)
        #expect(open.phase == .everyone)
        #expect(open.canSend)
        #expect(open.canReceive)
        #expect(open.opensLinks)

        var closed = everyone
        closed.notchOpen = false
        closed.receiveInBackground = "false"
        let shut = PortalDeviceBoardBuilder.make(closed)
        #expect(shut.canSend)
        #expect(!shut.canReceive)

        var hidden = everyone
        hidden.visibility = "Off"
        #expect(PortalDeviceBoardBuilder.make(hidden).phase == .hidden)
        #expect(!PortalDeviceBoardBuilder.make(hidden).canReceive)

        var unknown = everyone
        unknown.visibility = "Everyone Nearby"
        #expect(PortalDeviceBoardBuilder.make(unknown).phase == .hidden)

        var denied = everyone
        denied.localNetworkDenied = true
        let blocked = PortalDeviceBoardBuilder.make(denied)
        #expect(blocked.phase == .unavailable)
        #expect(!blocked.canSend)
        #expect(!blocked.canReceive)
        #expect(!blocked.opensLinks)

        var waiting = everyone
        waiting.peersKnown = false
        #expect(PortalDeviceBoardBuilder.make(waiting).phase == .loading)

        var paired = everyone
        paired.visibility = "Paired only"
        #expect(PortalDeviceBoardBuilder.make(paired).phase == .pairedOnly)
    }

    @Test func theListHasEmptyLoadingAndErrorCopy() {
        var empty = PortalFlingReading.off
        empty.enabled = "true"
        empty.visibility = "Paired only"
        empty.peersKnown = true
        let board = PortalDeviceBoardBuilder.make(empty)
        #expect(board.devices.isEmpty)
        #expect(board.status == "No paired devices yet.")
        let controls = PortalSectionModel.controls(for: board, flow: PortalDropFlow())
        #expect(controls.contains { $0.id == "portal.empty" })
        #expect(controls.allSatisfy { $0.keyboardReachable && !$0.label.isEmpty && !$0.helper.isEmpty })

        var loading = empty
        loading.peersKnown = false
        #expect(PortalDeviceBoardBuilder.make(loading).status == "Looking for paired devices.")

        var denied = empty
        denied.localNetworkDenied = true
        #expect(PortalDeviceBoardBuilder.make(denied).status == "Local network access is off, so nearby devices stay hidden.")
    }

    @Test func namesAndRemovalStayInline() {
        var reading = PortalFlingReading.off
        reading.enabled = "true"
        reading.visibility = "Paired only"
        reading.peersKnown = true
        reading.deviceName = "  Desk \n"
        reading.paired = [
            PortalPairedDevice(id: "b", name: "Beta", lastSeen: nil),
            PortalPairedDevice(id: "a", name: "Alpha", lastSeen: nil),
        ]
        let board = PortalDeviceBoardBuilder.make(reading)
        #expect(board.shownName == "Desk")
        #expect(board.devices.map(\.id) == ["a", "b"])
        let controls = PortalSectionModel.controls(for: board, flow: PortalDropFlow())
        #expect(controls.contains { $0.id == "portal.remove.a" && $0.label == "Remove Alpha" })

        var removal = PortalRemovalFlow()
        #expect(removal.ask(id: "missing", known: ["a"]) == .refused)
        #expect(removal.phase == .idle)
        #expect(removal.ask(id: "a", known: ["a"]) == .applied)
        #expect(removal.confirm() == .applied)
        #expect(removal.phase == .removed("a"))
        #expect(removal.dismiss() == .applied)
        #expect(removal.phase == .idle)

        var again = PortalRemovalFlow()
        _ = again.ask(id: "a", known: ["a"])
        #expect(again.dismiss() == .applied)
        #expect(again.phase == .idle)
        #expect(again.confirm() == .refused)
    }

    @Test func motionCollapsesAndThePreviewNamesThePhase() {
        #expect(PortalSectionMetrics.animationDuration(reduceMotion: true) == 0)
        #expect(PortalSectionMetrics.pressScale(reduceMotion: true) == 1)
        #expect(PortalSectionMetrics.animationDuration(reduceMotion: false) == MotionTokens.crossfadeDuration)
        #expect(PortalSectionMetrics.pressScale(reduceMotion: false) == MotionTokens.pressScale)
        let flow = PortalDropFlow()
        let preview = PortalSectionModel.preview(flow.phase, reduceMotion: true)
        #expect(preview.phase == "idle")
        #expect(preview.animationDuration == 0)
        #expect(preview.pressScale == 1)
        #expect(!preview.title.isEmpty)
        #expect(!preview.detail.isEmpty)
        let failed = PortalSectionModel.preview(.failed(.tooLarge), reduceMotion: false)
        #expect(failed.phase == "failed")
        #expect(failed.detail == PortalCopy.sentence(.tooLarge))
        #expect(failed.animationDuration > 0)
    }

    @Test func conversionSourcesDoNotReachForToolsOrTheNetwork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let folders = [
            root.appendingPathComponent("Sources/ZeusCore/Settings/Sections/Portal"),
            root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/Portal"),
        ]
        var sources: [String] = []
        for folder in folders {
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            for name in names where name.hasSuffix(".swift") {
                sources.append(try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))
            }
        }
        #expect(!sources.isEmpty)
        let hits = sources.flatMap { PortalToolBoundary.violations(in: $0) }
        #expect(hits.isEmpty)
        let view = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/PortalSettingsSection.swift"), encoding: .utf8)
        #expect(view.contains("GlassSettingsMetrics.panelPadding"))
        #expect(view.contains("GlassSettingsMetrics.cardSpacing"))
        #expect(view.contains("GlassSettingsMetrics.controlRow"))
        #expect(view.contains("GlassSettingsMetrics.helperLine"))
        #expect(view.contains("control.helper"))
        #expect(view.contains("control.label"))
        #expect(view.contains("accessibilityReduceMotion"))
        #expect(view.contains("focusable(true)"))
        #expect(!view.contains("accessibilityHidden(true)"))
        #expect(PortalToolBoundary.violations(in: view).isEmpty)
    }
}
