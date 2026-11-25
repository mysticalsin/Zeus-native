import Foundation

/// The question shown a few minutes before a meeting, and the detail behind it. Local only.
public enum MeetingPrompt {
    public static let defaultLeadMinutes = 5
    public static let minimumLeadMinutes = 5
    public static let maximumLeadMinutes = 10

    public struct Attendee: Equatable, Sendable {
        public var name: String
        public var role: String?
        public var company: String?
        public init(name: String, role: String? = nil, company: String? = nil) {
            self.name = name
            self.role = role
            self.company = company
        }
    }

    public struct Detail: Equatable, Sendable {
        public var purpose: String
        public var context: String
        public var attendees: [Attendee]
        public var callApp: String
        public var joinURL: String?
        public var collapsed: Bool
    }

    /// 5 to 10 minutes. Anything outside that range is pulled back in.
    public static func leadMinutes(_ minutes: Int) -> Int {
        min(maximumLeadMinutes, max(minimumLeadMinutes, minutes))
    }

    /// Minutes left, when the meeting is inside the lead window and still ahead. Otherwise nil.
    public static func minutesUntil(start: Date, now: Date, lead: Int = defaultLeadMinutes) -> Int? {
        let window = TimeInterval(leadMinutes(lead) * 60)
        let delta = start.timeIntervalSince(now)
        guard delta > 0, delta <= window else { return nil }
        return max(1, Int((delta / 60).rounded(.up)))
    }

    public static func line(name: String, minutes: Int) -> String {
        "Your meeting with \(name) starts in \(minutes) min. See it?"
    }

    /// Purpose and context are plain text. Shared or presenting hides the detail even after a click.
    /// Unknown capture hides it until the person opens it. Role and company need Contacts.
    public static func detail(purpose: String, context: String, attendees: [Attendee], callApp: String,
                              joinURL: String?, shared: Bool, presenting: Bool, captureKnown: Bool,
                              expanded: Bool, contactsAllowed: Bool) -> Detail {
        let forced = shared || presenting || !captureKnown
        let collapsed = shared || presenting || (forced && !expanded)
        let people = contactsAllowed && !collapsed
            ? attendees
            : attendees.map { Attendee(name: $0.name) }
        return Detail(purpose: collapsed ? "" : MeetingBrief.plain(purpose),
                      context: collapsed ? "" : MeetingBrief.plain(context),
                      attendees: collapsed ? [] : people,
                      callApp: collapsed ? "" : callApp,
                      joinURL: collapsed ? nil : joinURL,
                      collapsed: collapsed)
    }
}
