import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Card footer actions are readable")
struct CardFooterVisibilityTests {
    /// QA M9: "Copy" and "Save to Brain..." took the default text colour, which is black in an offscreen render
    /// and on the dark card, so the footer looked empty.
    @Test func theRoutineCardFooterActionsAreDrawnLight() throws {
        let run = RoutineRun(routineID: UUID(), routineName: "Weekday repo summary", date: Date(), engine: "codex",
                             output: "**3 repos changed** since yesterday:\n- zeus: stickies and routines landed",
                             failed: false)
        let probe = try #require(RenderedPixelProbe(RoutineCardView(run: run, dismiss: {}), width: 400))
        // The footer is the last text row: skip the 14 pt padding and the border.
        let footer = (probe.height - 14 - 16)..<(probe.height - 14)
        #expect(probe.brightPixels(rows: footer) > 60, "the Copy and Save to Brain actions are not visible on the card")
    }
}
