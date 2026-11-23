import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe manual start")
struct ScribeManualStartTests {
    @Test func anActiveRequestRefusesThenAClearWiresAppliesAndStartsTheProvider() {
        var start = ScribeManualStart()
        let refused = start.request(active: true)
        #expect(refused == [.refuse])
        #expect(start.state == .idle)

        let opened = start.request(active: false)
        #expect(opened == [.yieldCapture, .clearFields, .openStreams])
        #expect(start.state == .clearing)

        let cleared = start.fieldsCleared()
        #expect(cleared == [])
        #expect(start.state == .clearing)

        let apply = start.wired()
        #expect(apply == [.applyStart])
        #expect(start.state == .wired)

        var declined = start
        let none = declined.machineApplied(false)
        #expect(none == [])
        #expect(declined.state == .refused)

        let provider = start.machineApplied(true)
        #expect(provider == [.startProvider])
        #expect(start.state == .accepted)

        let again = start.machineApplied(true)
        #expect(again == [])
        #expect(start.state == .accepted)
    }
}
