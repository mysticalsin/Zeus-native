import Foundation

/// What a recording is told about the meeting it was started for. One value, passed to `ScribeController.start`,
/// so a refused start leaves nothing behind for the next recording to pick up.
public struct ScribeMeetingContext: Equatable, Sendable {
    /// The recap title. Nil keeps the plain "Meeting notes".
    public var title: String?
    /// Display names from the calendar invite, never email addresses.
    public var attendeeNames: [String]
    /// The call app's process, for the app-closed end rule. Only a recording started on a live call has one.
    public var callIdentity: ScribeCallProcessIdentity?

    public init(title: String? = nil, attendeeNames: [String] = [], callIdentity: ScribeCallProcessIdentity? = nil) {
        self.title = title
        self.attendeeNames = attendeeNames
        self.callIdentity = callIdentity
    }
}

extension ScribeMeeting {
    /// The context a recording of this meeting starts with. The title is the event's own, or "<App> call" for a
    /// call with no event; an empty title is none. A call binding is kept only for a live meeting.
    public func context(callIdentity: ScribeCallProcessIdentity?) -> ScribeMeetingContext {
        let title: String?
        if let slot {
            let trimmed = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmed.isEmpty ? nil : trimmed
        } else {
            title = callApp.map { "\(ScribeCallDetection.displayName($0)) call" }
        }
        return ScribeMeetingContext(title: title, attendeeNames: ScribeAttendeeNames.clean(slot?.attendeeNames ?? []),
                                    callIdentity: isLive ? callIdentity : nil)
    }
}
