import Testing
@testable import ZeusCore

@Suite("Drive typing interruption")
@MainActor
struct DriveTypingFlowTests {
    @Test func cancellationDuringFocusDelayPreventsSelectAllAndTyping() async {
        var ownsInput = true
        var effects: [String] = []
        let result = await DriveTypingFlow.run(
            chunks: ["replacement"], replacing: true, mayEmit: { ownsInput },
            sleep: { _ in ownsInput = false }, selectAll: { effects.append("selectAll") },
            delete: { effects.append("delete") }, type: { effects.append($0) }
        )
        #expect(result == .interrupted(piecesTyped: 0))
        #expect(effects.isEmpty)
    }

    @Test func focusDriftBetweenChunksStopsBeforeWritingIntoTheNewField() async {
        var focus = "intended field"
        var effects: [String] = []
        let result = await DriveTypingFlow.run(
            chunks: ["first", "second"], replacing: false, mayEmit: { focus == "intended field" },
            sleep: { delay in if delay == 12 { focus = "other field" } },
            selectAll: { effects.append("selectAll") }, delete: { effects.append("delete") },
            type: { effects.append($0) }
        )
        #expect(result == .interrupted(piecesTyped: 1))
        #expect(effects == ["first"])
    }

    @Test func clearingRechecksFocusAfterSelectAll() async {
        var focusMatches = true
        var effects: [String] = []
        let result = await DriveTypingFlow.run(
            chunks: [], replacing: true, mayEmit: { focusMatches }, sleep: { _ in },
            selectAll: { effects.append("selectAll"); focusMatches = false },
            delete: { effects.append("delete") }, type: { effects.append($0) }
        )
        #expect(result == .interrupted(piecesTyped: 0))
        #expect(effects == ["selectAll"])
    }

    @Test func stableOwnershipReplacesAndClearsInOrder() async {
        var effects: [String] = []
        let replaced = await DriveTypingFlow.run(
            chunks: ["first", "second"], replacing: true, mayEmit: { true }, sleep: { _ in },
            selectAll: { effects.append("selectAll") }, delete: { effects.append("delete") },
            type: { effects.append($0) }
        )
        #expect(replaced == .typed)
        #expect(effects == ["selectAll", "first", "second"])
        effects = []
        let cleared = await DriveTypingFlow.run(
            chunks: [], replacing: true, mayEmit: { true }, sleep: { _ in },
            selectAll: { effects.append("selectAll") }, delete: { effects.append("delete") },
            type: { effects.append($0) }
        )
        #expect(cleared == .typed)
        #expect(effects == ["selectAll", "delete"])
    }

    @Test func onlyExplicitlyAttributedEventsRetainAgentOwnership() {
        #expect(DriveInputAttribution.isOwnEvent(userData: DriveInputAttribution.eventTag))
        #expect(!DriveInputAttribution.isOwnEvent(userData: nil))
        #expect(!DriveInputAttribution.isOwnEvent(userData: 0))
        #expect(!DriveInputAttribution.isOwnEvent(userData: 1))
    }
}
