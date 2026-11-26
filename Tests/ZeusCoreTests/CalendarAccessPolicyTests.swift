import Testing
@testable import ZeusCore

@Suite struct CalendarAccessPolicyTests {
    private final class Asks: @unchecked Sendable {
        var count = 0
    }

    @Test func thePermissionsDeskTheBriefAndTheTopBarDoNotAsk() async {
        for caller in [CalendarAccessCaller.permissionsDesk, .proactiveBrief, .topBar] {
            let asks = Asks()
            let granted = await CalendarAccessPolicy.requestFullAccess(from: caller, alreadyGranted: false) {
                asks.count += 1
                return true
            }
            #expect(!CalendarAccessPolicy.mayRequestFullAccess(caller))
            #expect(asks.count == 0)
            #expect(!granted)
        }
    }

    @Test func theAgendaToggleIsTheOnlyAsk() async {
        let asks = Asks()
        let granted = await CalendarAccessPolicy.requestFullAccess(from: .agendaToggle, alreadyGranted: false) {
            asks.count += 1
            return true
        }
        #expect(CalendarAccessPolicy.mayRequestFullAccess(.agendaToggle))
        #expect(asks.count == 1)
        #expect(granted)
    }

    @Test func anExistingGrantDoesNotAskAgain() async {
        let asks = Asks()
        let granted = await CalendarAccessPolicy.requestFullAccess(from: .agendaToggle, alreadyGranted: true) {
            asks.count += 1
            return false
        }
        #expect(asks.count == 0)
        #expect(granted)
    }

    @Test func thePermissionsNoteMatchesTheAsk() {
        let note = CalendarAccessPolicy.permissionsNote
        #expect(note.contains("Asked only when you turn the agenda on"))
        #expect(note.contains("Read only"))
        #expect(!note.contains("permissions desk"))
        #expect(!note.contains("morning brief"))
        #expect(!note.contains("top bar"))
    }
}
