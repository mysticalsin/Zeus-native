import Testing
@testable import ZeusCore

@Suite struct PlayDemoScriptTests {
    @Test func theListeningAndThinkingBeatsAreSpokenAndShown() {
        for step in [PlayDemoScript.listening, PlayDemoScript.thinking] {
            #expect(PlayDemoScript.ready(step))
            #expect(step.showsOnScreen)
            #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
            #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
        }
        #expect(PlayDemoScript.listening.bolt == "Listening")
        #expect(PlayDemoScript.thinking.bolt == "Thinking")
        #expect(PlayDemoScript.listening.spoken == "Hold the talk key, then speak. I'll listen.")
        #expect(PlayDemoScript.thinking.spoken == "One moment. I'm working out what to show you.")
    }

    @Test func theMenuBarDemoIsSpokenAndShown() {
        let step = PlayDemoScript.menuBar
        #expect(PlayDemoScript.ready(step))
        #expect(step.showsOnScreen)
        #expect(step.spoken == "That's me up here. Click the bolt anytime.")
        #expect(step.bolt == "Click the bolt anytime")
        #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
        #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
    }

    @Test func theApprovalDemoIsSpokenAndShown() {
        let step = PlayDemoScript.approval
        #expect(PlayDemoScript.ready(step))
        #expect(step.showsOnScreen)
        #expect(step.spoken == "This needs you. Approve or deny, or just say ok.")
        #expect(step.bolt == "Approve or deny, or say ok")
        #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
        #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
    }

    @Test func aStartedBuildAndAMissingApproveAreSpokenAndShown() {
        for step in [PlayDemoScript.building, PlayDemoScript.approvalMissing] {
            #expect(PlayDemoScript.ready(step))
            #expect(step.showsOnScreen)
            #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
            #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
        }
        #expect(PlayDemoScript.building.bolt == "Building")
        #expect(PlayDemoScript.approvalMissing.bolt == "Not found")
        #expect(PlayDemoScript.building.spoken == "Claude Code started the build. I'll point at Approve when it asks.")
        #expect(PlayDemoScript.approvalMissing.spoken == "I couldn't find Approve on screen, so I'll keep going.")
    }

    @Test func theBuildOutcomeIsSpokenAndShown() {
        for step in [PlayDemoScript.allowed, PlayDemoScript.denied] {
            #expect(PlayDemoScript.ready(step))
            #expect(step.showsOnScreen)
            #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
            #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
        }
        #expect(PlayDemoScript.allowed.bolt == "Allowed")
        #expect(PlayDemoScript.denied.bolt == "Denied")
        #expect(PlayDemoScript.allowed.spoken == "Allowed. The build is running, and I'll show you when it finishes.")
        #expect(PlayDemoScript.denied.spoken == "Denied. I left that command alone, so nothing was removed.")
    }

    @Test func thePanelPeekAndCloseAreSpokenAndShown() {
        for step in [PlayDemoScript.panel, PlayDemoScript.peek, PlayDemoScript.closed] {
            #expect(PlayDemoScript.ready(step))
            #expect(step.showsOnScreen)
            #expect(PointerGuideCaptionSplit.boltText(step.bolt) == step.bolt)
            #expect(PointerGuideCaptionSplit.boltText(step.spoken) == nil)
        }
        #expect(PlayDemoScript.panel.bolt == "More agents")
        #expect(PlayDemoScript.peek.bolt == "Codex")
        #expect(PlayDemoScript.closed.bolt == "Closed")
        #expect(PlayDemoScript.panel.spoken == "Codex and Cursor are working too. I'll open the panel.")
        #expect(PlayDemoScript.peek.spoken == "Here's Codex. It's writing tests for checkout.")
        #expect(PlayDemoScript.closed.spoken == "That's the tour. I'll put the notch away.")
    }

    @Test func aStepThatIsNotDrawnIsNotReady() {
        let spokenOnly = PlayDemoScript.Step(
            spoken: "Click the bolt anytime",
            bolt: "Click the bolt anytime",
            showsOnScreen: false)
        #expect(PlayDemoScript.ready(spokenOnly) == false)
        let wall = PlayDemoScript.Step(
            spoken: "That's me up here.",
            bolt: String(repeating: "a", count: 41),
            showsOnScreen: true)
        #expect(PlayDemoScript.ready(wall) == false)
    }
}
