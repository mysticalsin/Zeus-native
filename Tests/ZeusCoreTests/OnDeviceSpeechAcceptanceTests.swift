import Testing
@testable import ZeusCore

@Suite struct OnDeviceSpeechAcceptanceTests {
    @Test func liveWordsHudStreamsRevisions() {
        var hud = LiveWordsHUD()
        hud.applyPartial("hey")
        hud.applyPartial("hey zeus")
        #expect(hud.visible == "hey zeus")
        #expect(hud.updates == 2)
        hud.applyPartial("hey zeus")
        #expect(hud.updates == 2)
    }

    @Test func revisedPartialBlocksExtraActions() {
        var recorder = PartialActionRecorder()
        recorder.observePartial("open slack")
        recorder.tryAct(on: "open slack")
        recorder.observePartial("open calculator")
        recorder.tryAct(on: "open slack")
        #expect(recorder.actions == 1)
    }

    @Test func acceptanceReportPasses() {
        let report = OnDeviceSpeechAcceptance.report()
        #expect(report.passed)
        #expect(report.text.contains("ondevice=required"))
    }
}
