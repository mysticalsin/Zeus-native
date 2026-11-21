import Foundation
import Testing
@testable import ZeusCore

/// The hub screen and the session groups. The target tables are the oracle:
/// a pair that is not in a table leaves the state as it was.
@Suite("Hub screen")
struct HubScreenTests {
    @Test func noSessionsAndAFailedSocketIsConnectionError() {
        let opened = HubScreenMachine.next(
            HubScreenState(screen: .loading),
            .socketOpenedNoSessions,
            context: HubScreenContext(sessionCount: 0)
        )
        #expect(opened.screen == .empty)
        for from: HubScreen in [.loading, .ready] {
            let failed = HubScreenMachine.next(
                HubScreenState(screen: from),
                .socketFailed,
                context: HubScreenContext(sessionCount: 0)
            )
            #expect(failed.screen == .connectionError)
            #expect(failed.screen != .empty)
            #expect(HubScreenMachine.copy(failed).sentence == "Agents aren't connected.")
            #expect(HubScreenMachine.copy(failed).actionTitle == "Try again")
        }
        #expect(HubScreenMachine.copy(opened).actionTitle == "New chat")
        #expect(HubScreenMachine.copy(opened).sentence != "Agents aren't connected.")
    }

    @Test func emptyCopyContainsNoProductTitle() {
        let copy = HubScreenMachine.copy(HubScreenState(screen: .empty))
        #expect(copy.sentence == "Nothing running")
        #expect(copy.detail == "Start a chat and it shows up here.")
        #expect(copy.actionTitle == "New chat")
        let words = [copy.sentence, copy.detail, copy.actionTitle]
            .compactMap { $0 }
            .joined(separator: " ")
            .split(separator: " ")
            .map(String.init)
        #expect(words == ["Nothing", "running", "Start", "a", "chat", "and", "it", "shows", "up", "here.", "New", "chat"])

        let loading = HubScreenMachine.copy(HubScreenState(screen: .loading))
        let failure = HubScreenMachine.copy(HubScreenState(screen: .connectionError))
        #expect(loading.sentence == "Connecting…")
        #expect(loading.detail == nil)
        #expect(loading.actionTitle == nil)
        #expect(failure.sentence == "Agents aren't connected.")
        #expect(failure.actionTitle == "Try again")
        #expect(failure.sentence != copy.sentence)
        #expect(copy.actionTitle != failure.actionTitle)
        #expect(HubScreenMachine.copy(HubScreenState(screen: .ready)).sentence == nil)
        #expect(HubScreenMachine.copy(HubScreenState(screen: .ready)).actionTitle == nil)
    }

    @Test func screenTable() {
        let rows: [(HubScreen, HubScreenEvent, Int, HubScreen)] = [
            (.empty, .socketOpenedNoSessions, 0, .empty),
            (.empty, .socketOpening, 0, .loading),
            (.empty, .sessionArrived, 1, .ready),
            (.loading, .socketOpenedNoSessions, 0, .empty),
            (.loading, .atLeastOneSession, 1, .ready),
            (.loading, .socketFailed, 0, .connectionError),
            (.loading, .socketFailed, 2, .connectionError),
            (.ready, .lastSessionEnded, 0, .empty),
            (.ready, .socketFailed, 2, .connectionError),
            (.ready, .socketFailed, 0, .connectionError),
            (.connectionError, .tryAgain, 0, .loading),
            (.connectionError, .socketOpened, 0, .empty),
            (.connectionError, .socketOpened, 3, .ready),
        ]
        for (from, event, count, to) in rows {
            let next = HubScreenMachine.next(
                HubScreenState(screen: from, reason: "old", chatForm: true),
                event,
                context: HubScreenContext(sessionCount: count, failureSentence: "The socket closed.")
            )
            #expect(next.screen == to)
            if to == .connectionError {
                #expect(next.reason == "The socket closed.")
            } else {
                #expect(next.reason == nil)
            }
            #expect(next.chatForm == (to == from))
        }
    }

    @Test func aMissingPairDoesNotChangeTheScreen() {
        let rows: [(HubScreen, HubScreenEvent, Int)] = [
            (.empty, .socketFailed, 0),
            (.empty, .atLeastOneSession, 1),
            (.empty, .tryAgain, 0),
            (.empty, .lastSessionEnded, 0),
            (.empty, .socketOpened, 0),
            (.loading, .sessionArrived, 1),
            (.loading, .lastSessionEnded, 0),
            (.loading, .tryAgain, 0),
            (.loading, .socketOpened, 1),
            (.ready, .socketOpening, 1),
            (.ready, .socketOpenedNoSessions, 0),
            (.ready, .sessionArrived, 2),
            (.ready, .tryAgain, 1),
            (.ready, .socketOpened, 1),
            (.ready, .atLeastOneSession, 1),
            (.connectionError, .socketFailed, 0),
            (.connectionError, .sessionArrived, 1),
            (.connectionError, .lastSessionEnded, 0),
            (.connectionError, .socketOpening, 0),
            (.connectionError, .socketOpenedNoSessions, 0),
            (.connectionError, .atLeastOneSession, 2),
        ]
        for (from, event, count) in rows {
            let state = HubScreenState(
                screen: from,
                reason: from == .connectionError ? "The socket closed." : nil,
                chatForm: true
            )
            let next = HubScreenMachine.next(state, event, context: HubScreenContext(sessionCount: count, failureSentence: "other"))
            #expect(next == state)
        }
    }

    @Test func newChatRemembersTheHubPhase() {
        for phase in HubScreen.allCases {
            let state = HubScreenState(screen: phase, reason: phase == .connectionError ? "The socket closed." : nil)
            let opened = HubScreenMachine.next(state, .newChat, context: HubScreenContext(onChatTab: true))
            #expect(opened.screen == phase)
            #expect(opened.reason == state.reason)
            #expect(opened.chatForm)
            let refused = HubScreenMachine.next(state, .newChat, context: HubScreenContext(onChatTab: false))
            #expect(refused == state)
        }
    }

    @Test func aSocketSentenceWithAPathIsNotShown() {
        let kept = HubScreenMachine.next(
            HubScreenState(screen: .loading),
            .socketFailed,
            context: HubScreenContext(sessionCount: 0, failureSentence: "  The socket closed.  ")
        )
        #expect(kept.reason == "The socket closed.")
        #expect(HubScreenMachine.copy(kept).detail == "The socket closed.")
        #expect(HubScreenMachine.copy(kept).sentence == "Agents aren't connected.")

        let dropped = HubScreenMachine.next(
            HubScreenState(screen: .loading),
            .socketFailed,
            context: HubScreenContext(sessionCount: 0, failureSentence: "closed /var/run/hub.sock")
        )
        #expect(dropped.screen == .connectionError)
        #expect(dropped.reason == nil)
        #expect(HubScreenMachine.copy(dropped).detail == nil)

        let home = HubScreenMachine.next(
            HubScreenState(screen: .ready),
            .socketFailed,
            context: HubScreenContext(sessionCount: 1, failureSentence: "closed ~/hub.sock")
        )
        #expect(home.screen == .connectionError)
        #expect(home.reason == nil)
    }

    @Test func tryAgainThenTheOpenSocketFollowsTheSessionCount() {
        let failed = HubScreenMachine.next(
            HubScreenState(screen: .empty),
            .socketOpening,
            context: HubScreenContext()
        )
        let error = HubScreenMachine.next(failed, .socketFailed, context: HubScreenContext(failureSentence: "The socket closed."))
        #expect(error.screen == .connectionError)
        let retry = HubScreenMachine.next(error, .tryAgain, context: HubScreenContext())
        #expect(retry == HubScreenState(screen: .loading))
        let stillLoading = HubScreenMachine.next(retry, .socketOpened, context: HubScreenContext(sessionCount: 0))
        #expect(stillLoading.screen == .loading)
        let recovered = HubScreenMachine.next(error, .socketOpened, context: HubScreenContext(sessionCount: 0))
        #expect(recovered.screen == .empty)
        #expect(recovered.reason == nil)
        let ready = HubScreenMachine.next(error, .socketOpened, context: HubScreenContext(sessionCount: 1))
        #expect(ready.screen == .ready)
        #expect(ready.reason == nil)
    }

    @Test func firstLoadExpandsOnlyTheMostUrgentGroup() {
        let north = session("n", "North", "api", .running, elapsed: 10)
        let south = session("s", "South", "web", .needsApproval, elapsed: 3)
        let east = session("e", "East", "docs", .error(.quiet), elapsed: 52)
        let state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [north, south, east])
        #expect(state.groups.map(\.agent) == ["South", "East", "North"])
        #expect(state.groups.map(\.status) == [.expanded, .collapsed, .collapsed])
        #expect(state.groups.filter { $0.status == .expanded }.map(\.agent) == ["South"])
        #expect(state.groups[1].mostUrgent.elapsedSeconds == 52)

        let tied = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [
            session("m", "Moth", "api", .running),
            session("b", "Bee", "api", .error(.quiet)),
            session("a", "Ant", "api", .error(.failed)),
        ])
        #expect(tied.groups.map(\.agent) == ["Ant", "Bee", "Moth"])
        #expect(tied.groups.map(\.status) == [.expanded, .collapsed, .collapsed])

        var expanded = state
        expanded = HubGroupMachine.next(expanded, .activateHeader, header: "North")
        expanded = HubGroupMachine.next(expanded, .activateHeader, header: "East")
        #expect(expanded.groups.allSatisfy { $0.status == .expanded })
        let again = HubGroupMachine.next(expanded, .firstLoad, sessions: [north, south, east])
        #expect(again.groups.map(\.status) == [.expanded, .collapsed, .collapsed])
        #expect(again.groups[0].agent == "South")
    }

    @Test func removingAGroupsLastSessionRemovesItsHeaderAndKeepsOtherExpandedFlags() {
        let north = session("n", "North", "api", .running)
        let south = session("s", "South", "web", .needsApproval)
        let east = session("e", "East", "docs", .done)
        var state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [north, south, east])
        state = HubGroupMachine.next(state, .activateHeader, header: "North")
        #expect(state.groups.map(\.agent) == ["South", "North", "East"])
        #expect(state.groups.map(\.status) == [.expanded, .expanded, .collapsed])

        state = HubGroupMachine.next(state, .lostLastSession, sessions: [north, east], header: "South")
        #expect(state.groups.map(\.agent) == ["North", "East"])
        #expect(state.groups.map(\.status) == [.expanded, .collapsed])
        #expect(state.groups.contains { $0.agent == "South" } == false)

        let kept = HubGroupMachine.next(state, .lostLastSession, sessions: [
            session("n", "North", "api", .done), east,
        ], header: "North")
        #expect(kept == state)
    }

    @Test func aGroupOfOneIsStillAHeader() {
        let first = session("a", "Ada", "api", .running, elapsed: 4)
        let state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [first])
        #expect(state.groups.count == 1)
        #expect(state.groups[0].count == 1)
        #expect(state.groups[0].status == .expanded)
        #expect(state.groups[0].projects.map(\.project) == ["api"])

        let second = session("b", "Ada", "docs", .waitingForInput, elapsed: 9)
        let next = HubGroupMachine.next(state, .sessionsChanged, sessions: [first, second])
        #expect(next.groups.count == 1)
        #expect(next.groups[0].count == 2)
        #expect(next.groups[0].status == .expanded)
        #expect(next.groups[0].projects.map(\.project) == ["docs", "api"])
        #expect(next.groups[0].mostUrgent.id == "b")
        #expect(next.groups[0].mostUrgent.elapsedSeconds == 9)
    }

    @Test func sessionsChangedKeepsTheExpandedSet() {
        let ada = session("a", "Ada", "api", .running)
        let bee = session("b", "Bee", "web", .done)
        var state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [ada, bee])
        #expect(state.groups.map(\.agent) == ["Ada", "Bee"])
        #expect(state.groups.map(\.status) == [.expanded, .collapsed])
        state = HubGroupMachine.next(state, .activateHeader, header: "Bee")
        let added = session("c", "Ada", "docs", .needsApproval)
        let cy = session("d", "Cy", "api", .loading)
        state = HubGroupMachine.next(state, .sessionsChanged, sessions: [ada, added, bee, cy])
        #expect(state.groups.map(\.agent) == ["Ada", "Bee", "Cy"])
        #expect(state.groups.map(\.status) == [.expanded, .expanded, .collapsed])
        #expect(state.groups[0].count == 2)
        #expect(state.groups[0].mostUrgent.status == .needsApproval)
    }

    @Test func activateHeaderTogglesAndIgnoresAMissingHeader() {
        let ada = session("a", "Ada", "api", .running)
        var state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [ada])
        #expect(state.groups[0].status == .expanded)
        state = HubGroupMachine.next(state, .activateHeader, header: "Ada")
        #expect(state.groups[0].status == .collapsed)
        state = HubGroupMachine.next(state, .activateHeader, header: "Ada")
        #expect(state.groups[0].status == .expanded)
        let missed = HubGroupMachine.next(state, .activateHeader, header: "Nobody")
        #expect(missed == state)
        let unnamed = HubGroupMachine.next(state, .activateHeader)
        #expect(unnamed == state)
    }

    @Test func headersWithNoSessionsAreNotDrawn() {
        #expect(HubGroupState().groups.isEmpty)
        let absent = session("a", "Ada", "api", .absent)
        let loaded = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [absent])
        #expect(loaded.groups.isEmpty)
        let ada = session("b", "Ada", "api", .running)
        let bee = session("c", "Bee", "web", .done)
        var state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [ada, bee])
        state = HubGroupMachine.next(state, .activateHeader, header: "Bee")
        let dropped = HubGroupMachine.next(state, .sessionsChanged, sessions: [
            session("b", "Ada", "api", .absent), bee,
        ])
        #expect(dropped.groups.map(\.agent) == ["Bee"])
        #expect(dropped.groups.map(\.status) == [.expanded])
    }

    @Test func removingOneProjectKeepsTheAgentHeader() {
        let api = session("a", "Ada", "api", .running)
        let docs = session("d", "Ada", "docs", .needsApproval, elapsed: 12)
        var state = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: [api, docs])
        #expect(state.groups.count == 1)
        #expect(state.groups[0].projects.map(\.project) == ["docs", "api"])
        #expect(state.groups[0].mostUrgent.elapsedSeconds == 12)
        let kept = HubGroupMachine.next(state, .lostLastSession, sessions: [api], header: "Ada")
        #expect(kept == state)
        state = HubGroupMachine.next(state, .sessionsChanged, sessions: [api])
        #expect(state.groups.map(\.agent) == ["Ada"])
        #expect(state.groups[0].status == .expanded)
        #expect(state.groups[0].projects.map(\.project) == ["api"])
        #expect(state.groups[0].count == 1)
    }

    private func session(
        _ id: String, _ agent: String, _ project: String, _ status: HubSessionStatus, elapsed: Int? = nil
    ) -> HubGroupSession {
        HubGroupSession(id: id, agent: agent, project: project, status: status, elapsedSeconds: elapsed)
    }
}
