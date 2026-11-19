import SwiftUI
import ZeusCore

// Still fixtures of the meeting card for `Zeus --snapshots`: every state with synthetic meetings, the hover
// variant, the Reduce Transparency still, a card with no call link and cards over a busy colourful backdrop so
// the glass shows. No service, clock or panel is involved.

@MainActor
enum ScribeMeetingCardFixture {
    typealias M = ScribeMeetingCardMetrics

    struct Entry {
        let name: String
        let card: ScribeMeetingCard
        let uptime: TimeInterval
        var hovered = false
        var reduceTransparency = false
        var busy = false
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// The window plus a margin of backdrop on every side.
    static let size = CGSize(width: M.windowSize.width + 72, height: M.windowSize.height + 72)
    private static let uptime: TimeInterval = 100
    private static let locale = Locale(identifier: "en_US")
    private static let timeZone = TimeZone(identifier: "UTC") ?? .current

    /// A link on the host of the first call brand, so the real resolver finds the apps this Mac has for it.
    private static let link: URL = {
        let host = AppBrandCatalog.brands.lazy.compactMap(\.linkHosts.first).first ?? "example.org"
        return URL(string: "https://\(host)/meeting/fixture")!
    }()

    private static func meeting(_ title: String = "Product Strategy Sync", startsIn: TimeInterval = 120,
                                linked: Bool = true) -> ScribeMeeting {
        let start = now.addingTimeInterval(startsIn)
        let guests = (1...11).map { "Guest \($0)" }
        let slot = ScribeCalendarSlot(id: "fixture-\(title)-\(linked)", title: title, start: start,
                                      end: start.addingTimeInterval(2_700), attendeeNames: guests,
                                      hasCallLink: linked, callLink: linked ? link : nil)
        return ScribeMeeting(key: slot.id, title: title, callApp: .other("Synthetic"), slot: slot)
    }

    private static func countdown(_ seconds: Int) -> ScribeMeetingCard {
        .countdown(meeting(startsIn: 0), seconds: seconds, deadline: uptime + Double(seconds), total: 5)
    }

    static let entries: [Entry] = {
        let long = meeting("Quarterly planning review with the whole regional leadership team")
        let rows: [Entry] = [
            Entry(name: "offer", card: .offer(meeting(), blocked: nil), uptime: uptime),
            Entry(name: "offer-hover", card: .offer(meeting(), blocked: nil), uptime: uptime, hovered: true),
            Entry(name: "offer-busy", card: .offer(meeting(), blocked: nil), uptime: uptime, busy: true),
            Entry(name: "offer-hover-busy", card: .offer(meeting(), blocked: nil), uptime: uptime, hovered: true, busy: true),
            Entry(name: "offer-reduce-transparency", card: .offer(meeting(), blocked: nil), uptime: uptime,
                  reduceTransparency: true),
            Entry(name: "offer-no-link", card: .offer(meeting(linked: false), blocked: nil), uptime: uptime),
            Entry(name: "offer-long-title", card: .offer(long, blocked: nil), uptime: uptime),
            Entry(name: "offer-now", card: .offer(meeting(startsIn: 0), blocked: nil), uptime: uptime),
            Entry(name: "offer-blocked-microphone-not-asked", card: .offer(meeting(), blocked: .microphoneNotAsked), uptime: uptime),
            Entry(name: "offer-blocked-microphone-denied", card: .offer(meeting(), blocked: .microphoneDenied), uptime: uptime),
            Entry(name: "offer-blocked-first-recording", card: .offer(meeting(), blocked: .firstRecordingOwed), uptime: uptime),
            Entry(name: "countdown-5", card: countdown(5), uptime: uptime),
            Entry(name: "countdown-3", card: countdown(3), uptime: uptime),
            Entry(name: "countdown-1", card: countdown(1), uptime: uptime),
            Entry(name: "countdown-3-busy", card: countdown(3), uptime: uptime, busy: true),
            Entry(name: "waiting", card: .waiting(meeting(startsIn: 0)), uptime: uptime),
            Entry(name: "starting-cancellable", card: .starting(meeting(startsIn: 0), cancellable: true), uptime: uptime),
            Entry(name: "starting", card: .starting(meeting(startsIn: 0), cancellable: false), uptime: uptime),
            Entry(name: "recording", card: .recording(meeting(startsIn: 0)), uptime: uptime),
            Entry(name: "recording-busy", card: .recording(meeting(startsIn: 0)), uptime: uptime, busy: true),
            Entry(name: "failed-microphone-off", card: .failed(meeting(startsIn: 0), .microphoneOff), uptime: uptime),
            Entry(name: "failed-microphone-off-hover", card: .failed(meeting(startsIn: 0), .microphoneOff), uptime: uptime,
                  hovered: true),
            Entry(name: "failed-still-saving", card: .failed(meeting(startsIn: 0), .stillSaving), uptime: uptime),
            Entry(name: "failed-capture", card: .failed(meeting(startsIn: 0), .captureFailed("No input device is available")),
                  uptime: uptime),
            Entry(name: "failed-no-response", card: .failed(meeting(startsIn: 0), .noResponse), uptime: uptime),
            Entry(name: "next", card: .next(meeting("Design review", startsIn: 60)), uptime: uptime),
            Entry(name: "next-now", card: .next(meeting("Design review", startsIn: 0)), uptime: uptime),
        ]
        return rows.map { Entry(name: "meeting-card-\($0.name)", card: $0.card, uptime: $0.uptime, hovered: $0.hovered,
                                reduceTransparency: $0.reduceTransparency, busy: $0.busy) }
    }()

    /// The card over its backdrop, drawn as it rests. A still has no desktop to blur, so a blurred copy of the
    /// backdrop is laid under the slab, which is what the system does behind the real window.
    static func view(_ entry: Entry) -> some View {
        let apps = entry.card.meeting.map { ScribeJoinAppResolver.shared.apps(for: $0) } ?? []
        let slab = RoundedRectangle(cornerRadius: M.cornerRadius, style: .continuous)
        return ZStack {
            Backdrop(busy: entry.busy)
            if !entry.reduceTransparency {
                Backdrop(busy: entry.busy)
                    .blur(radius: 26)
                    .mask { slab.frame(width: M.width, height: M.height) }
            }
            ScribeMeetingCardView(card: entry.card, now: now, uptime: entry.uptime, settled: true, joinApps: apps,
                                  hovered: entry.hovered, reduceMotion: false,
                                  reduceTransparency: entry.reduceTransparency, locale: locale, timeZone: timeZone)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// A calm blue-violet wallpaper, or a busy one: tiles of every colour with bars like text, so the blur and
    /// the tint of the glass are easy to judge.
    private struct Backdrop: View {
        let busy: Bool

        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x7C9CF8), Color(hex: 0x4663D8), Color(hex: 0x1B2C86)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color(hex: 0xA68BFF).opacity(0.7)).frame(width: 260, height: 150)
                    .blur(radius: 40).offset(x: 190, y: -70)
                Ellipse().fill(Color(hex: 0x2AD0FF).opacity(0.45)).frame(width: 300, height: 120)
                    .blur(radius: 40).offset(x: -170, y: 90)
                if busy { busyLayer }
            }
        }

        private var busyLayer: some View {
            VStack(spacing: 6) {
                ForEach(0..<9, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<12, id: \.self) { column in
                            let hue = Double((row * 5 + column * 3) % 17) / 17
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(hue: hue, saturation: 0.85, brightness: 0.95))
                                .frame(width: 44, height: (row + column) % 3 == 0 ? 22 : 12)
                        }
                    }
                }
            }
        }
    }
}
