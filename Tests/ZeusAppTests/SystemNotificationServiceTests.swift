import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("System notification permission flow")
struct SystemNotificationServiceTests {
    @MainActor
    private final class FakeClient: SystemNotificationClient {
        var status: SystemNotificationAuthorization = .notDetermined
        var grantsRequest = true
        var requestCount = 0
        var delivered: [SystemNotificationPayload] = []
        var openedSettings = 0

        func authorizationStatus() async -> SystemNotificationAuthorization { status }

        func requestAuthorization() async -> Bool {
            requestCount += 1
            status = grantsRequest ? .authorized : .denied
            return grantsRequest
        }

        func deliver(_ payload: SystemNotificationPayload) async { delivered.append(payload) }
        func openSystemSettings() { openedSettings += 1 }
    }

    /// Item 8's crash fix: in snapshot mode `.shared` uses this client instead of one backed by
    /// `UNUserNotificationCenter`, so rendering the Notifications page never touches it (and never
    /// crashes with "bundleProxyForCurrentProcess is nil" unbundled).
    @MainActor
    @Test func noopClientNeverPromptsOrDelivers() async {
        let client = NoopNotificationClient()
        #expect(await client.authorizationStatus() == .unknown)
        #expect(await client.requestAuthorization() == false)
        await client.deliver(SystemNotificationPayload(title: "x", body: "y")) // must not throw/crash
        client.openSystemSettings() // no-op, must not crash
    }

    @MainActor
    @Test func refreshAndDeliveryNeverRequestPermission() async {
        var enabled = false
        let client = FakeClient()
        let service = SystemNotificationService(client: client, isEnabled: { enabled }, setEnabled: { enabled = $0 })

        await service.refreshAuthorization()
        await service.deliver(.rain(minutes: 8))

        #expect(client.requestCount == 0)
        #expect(client.delivered.isEmpty)
        #expect(!enabled)
    }

    @MainActor
    @Test func explicitEnableRequestsOnceThenDeliversAuthorizedCue() async {
        var enabled = false
        let client = FakeClient()
        let service = SystemNotificationService(client: client, isEnabled: { enabled }, setEnabled: { enabled = $0 })

        await service.setEnabledFromUserAction(true)
        await service.deliver(.rain(minutes: 8))

        #expect(client.requestCount == 1)
        #expect(enabled)
        #expect(client.delivered == [SystemNotificationPayload(title: "Rain soon", body: "Rain may start in 8 minutes.",
                                                               dedupeKey: "cue|Rain soon|Rain may start in 8 minutes.")])
    }

    @MainActor
    @Test func deniedPermissionDoesNotPromptAgainAndSettingsOpenIsExplicit() async {
        var enabled = false
        let client = FakeClient()
        client.status = .denied
        let service = SystemNotificationService(client: client, isEnabled: { enabled }, setEnabled: { enabled = $0 })

        await service.setEnabledFromUserAction(true)
        service.openSystemSettingsAfterUserAction()

        #expect(client.requestCount == 0)
        #expect(client.openedSettings == 1)
        #expect(!enabled)
        #expect(service.authorization == .denied)
    }

    /// REG-945: a cue shown again and again (the capture cue re-shows every 2 s, permission hints repeat)
    /// must not stack a new macOS banner each time. One banner per cue text per dedupe window.
    @MainActor
    @Test func repeatedCueDeliversOneBannerPerWindow() async {
        var enabled = true
        var now = Date(timeIntervalSince1970: 1_000_000)
        let client = FakeClient()
        client.status = .authorized
        let service = SystemNotificationService(client: client, isEnabled: { enabled }, setEnabled: { enabled = $0 },
                                                clock: { now })
        let capture = NotchCue.hint("A command-line request is capturing audio or screen")

        for _ in 0..<30 {
            await service.deliver(capture)
            now += 2
        }
        #expect(client.delivered.count == 1)

        await service.deliver(.hint("Something else"))
        #expect(client.delivered.count == 2)

        now += NotificationDedupe.defaultWindow
        await service.deliver(capture)
        #expect(client.delivered.count == 3)
    }

    /// REG-945: a repeat that does get through replaces the earlier banner instead of stacking another.
    @MainActor
    @Test func cueBannersCarryAStableReplaceKey() async {
        var enabled = true
        var now = Date(timeIntervalSince1970: 1_000_000)
        let client = FakeClient()
        client.status = .authorized
        let service = SystemNotificationService(client: client, isEnabled: { enabled }, setEnabled: { enabled = $0 },
                                                clock: { now })
        await service.deliver(.permission("Screen Recording is off for Zeus.", pane: "Privacy_ScreenCapture"))
        now += NotificationDedupe.defaultWindow + 1
        await service.deliver(.permission("Screen Recording is off for Zeus.", pane: "Privacy_ScreenCapture"))

        #expect(client.delivered.count == 2)
        let keys = client.delivered.compactMap(\.dedupeKey)
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
    }

    @Test func onlyFocusedCuesCreateSystemBannerPayloads() {
        #expect(SystemNotificationPayload.forCue(.usageAlert("Claude Code at 82%")) ==
                SystemNotificationPayload(title: "Usage limit getting close", body: "Claude Code at 82%"))
        #expect(SystemNotificationPayload.forCue(.focusFinished("Break")) ==
                SystemNotificationPayload(title: "Focus round complete", body: "Break"))
        #expect(SystemNotificationPayload.forCue(.copied("private text")) == nil)
    }

    @MainActor
    @Test func systemBannerHonorsCueSettingAndIgnoresUnsupportedCues() {
        #expect(!TopBarModel.systemNotificationAllowed(for: .rain(minutes: 8), lightEnabled: false))
        #expect(TopBarModel.systemNotificationAllowed(for: .rain(minutes: 8), lightEnabled: true))
        #expect(!TopBarModel.systemNotificationAllowed(for: .copied("private text"), lightEnabled: true))
    }
}
