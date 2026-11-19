import Testing
@testable import ZeusCore

@Suite("Permission desk")
struct PermissionDeskTests {
    @Test func eachCapabilityOpensItsOwnPane() {
        #expect(PermissionDesk.url(for: .microphone).hasSuffix("Privacy_Microphone"))
        #expect(PermissionDesk.url(for: .speech).hasSuffix("Privacy_SpeechRecognition"))
        #expect(PermissionDesk.url(for: .camera).hasSuffix("Privacy_Camera"))
        #expect(PermissionDesk.url(for: .screen).hasSuffix("Privacy_ScreenCapture"))
        #expect(PermissionDesk.url(for: .accessibility).hasSuffix("Privacy_Accessibility"))
        #expect(PermissionDesk.url(for: .automation).hasSuffix("Privacy_Automation"))
        #expect(PermissionDesk.url(for: .bluetooth).hasSuffix("Privacy_Bluetooth"))
        #expect(PermissionDesk.url(for: .localNetwork).hasSuffix("Privacy_LocalNetwork"))
        #expect(PermissionDesk.url(for: .fullDisk).hasSuffix("Privacy_AllFiles"))
        #expect(PermissionDesk.url(for: .calendar).hasSuffix("Privacy_Calendars"))
        #expect(PermissionDesk.rows.first { $0.kind == .screen }?.canPrompt == false)
        #expect(PermissionDesk.rows.first { $0.kind == .microphone }?.canPrompt == true)
    }

    @Test func grantEverythingWalksOnlyWhatIsMissing() {
        var status: [PermissionDesk.Kind: PermissionDesk.Status] = [.microphone: .allowed, .speech: .denied]
        #expect(PermissionDesk.nextMissing(status) == .speech)
        status[.speech] = .allowed
        #expect(PermissionDesk.nextMissing(status) == .camera)
        #expect(PermissionDesk.record(probe: .denied) == .denied)
        #expect(PermissionDesk.record(probe: .unknown) != .allowed)
    }

    @Test func oneCheckDecidesTheButton() {
        let allow = PermissionDesk.can(resource: .microphone, action: .advance, status: .unknown)
        #expect(allow.can)
        #expect(allow.reason == "Allow")
        let settings = PermissionDesk.can(resource: .screen, action: .advance, status: .denied)
        #expect(settings.can)
        #expect(settings.reason == "Open Settings")
        let done = PermissionDesk.can(resource: .microphone, action: .advance, status: .allowed)
        #expect(done.can == false)
        #expect(done.reason == "Allowed")
        let gone = PermissionDesk.can(resource: .camera, action: .describe, status: .unavailable)
        #expect(gone.can == false)
        #expect(gone.reason == "Unavailable")
    }
}
