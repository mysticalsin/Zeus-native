import Testing
@testable import Zeus

@Suite("Step zero lock panel")
struct StepZeroLockPanelTests {
    @Test func theCardDrawsWordsAButtonAndARuler() {
        #expect(StepZeroLockPanel.words == "Zeus probe")
        #expect(StepZeroLockPanel.button == "Press")
        #expect(StepZeroLockPanel.sharing == .none)
        #expect(StepZeroLockPanel.drawn == [.words, .button, .ruler])
        #expect(StepZeroLockPanel.Part.allCases == [.words, .button, .ruler])
        #expect(StepZeroLockPanel.rulerTicks == Array(0...10))
        #expect(StepZeroLockPanel.width == 360)
        #expect(StepZeroLockPanel.height == 88)
    }

    @Test func theRulerIgnoresClicks() {
        var counts = StepZeroLockPanel.Counts()
        #expect(StepZeroLockPanel.input(at: .ruler) == nil)
        #expect(StepZeroLockPanel.accept(.ruler, into: &counts) == false)
        #expect(counts == StepZeroLockPanel.Counts())
        #expect(StepZeroLockPanel.accept(.words, into: &counts))
        #expect(StepZeroLockPanel.accept(.button, into: &counts))
        #expect(counts.buttonActions == 1)
        #expect(counts.mouseDowns == 1)
        #expect(counts.keyEvents == 0)
    }

    @Test func aKeyIsACountWithNoCode() {
        var counts = StepZeroLockPanel.Counts()
        StepZeroLockPanel.record(.key, into: &counts)
        StepZeroLockPanel.record(.key, into: &counts)
        StepZeroLockPanel.record(.mouseDown, into: &counts)
        StepZeroLockPanel.record(.button, into: &counts)
        #expect(counts.buttonActions == 1)
        #expect(counts.mouseDowns == 1)
        #expect(counts.keyEvents == 2)
        let labels = Mirror(reflecting: counts).children.compactMap(\.label)
        #expect(labels == ["buttonActions", "mouseDowns", "keyEvents"])
        for child in Mirror(reflecting: counts).children {
            #expect(child.value is Int)
        }
        let key = StepZeroLockPanel.Input.key
        #expect(Mirror(reflecting: key).children.isEmpty)
    }

    @Test func theWindowFactsMatchTheLockPanelStyle() {
        let style = StepZeroLockPanel.Style.probe
        #expect(style.canBecomeKey == false)
        #expect(style.canBecomeMain == false)
        #expect(style.acceptsFirstMouse)
        #expect(style.ignoresMouseEvents == false)
        #expect(style.hidesOnDeactivate == false)
        #expect(style.isReleasedWhenClosed == false)
        #expect(style.hasShadow == false)
        #expect(style.registersDraggedTypes == false)
        #expect(style.borderless)
        #expect(style.nonactivating)
        #expect(style.buffered)
        #expect(style.deferCreation == false)
        #expect(style.stationary)
        #expect(style.ignoresCycle)
        #expect(style.fullScreenAuxiliary)
        #expect(style.joinsAllSpaces == false)
        #expect(style.shieldingLevel)
    }
}
