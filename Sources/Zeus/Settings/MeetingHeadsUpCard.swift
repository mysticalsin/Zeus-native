import SwiftUI
import ZeusCore

/// The live notification page's in-app heads-up. It shares keys with the snapshot page and the scheduler.
struct MeetingHeadsUpCard: View {
    private var prefs: ExtraPreferences { .shared }
    private static let leads = ["Off", "1 min before", "5 min before", "10 min before", "15 min before"]
    private static let leadValues = [0, 1, 5, 10, 15]

    var body: some View {
        GSCard("Meeting heads-up") {
            GSToggleRow(symbol: "calendar", title: "In-app heads-up",
                        text: "Off until you turn it on. Zeus only mentions events the app already has, and it never creates a calendar event.",
                        isOn: Binding(get: { prefs.meetingHeadsUp }, set: { prefs.meetingHeadsUp = $0 }))
            GSDivider()
            GSRow(symbol: "clock", title: "Meeting lead", text: "How early an in-app meeting is mentioned. Off means no meeting heads-up.") {
                GSPopup(selection: Binding(
                    get: { Self.title(for: prefs.calendarLeadMinutes) },
                    set: { title in
                        if let index = Self.leads.firstIndex(of: title) {
                            prefs.calendarLeadMinutes = Self.leadValues[index]
                        }
                    }
                ), options: Self.leads, label: "Meeting lead")
            }
            GSDivider()
            GSToggleRow(symbol: "checklist", title: "Reminders", text: "In-app reminders only.",
                        isOn: Binding(get: { prefs.peekReminders }, set: { prefs.peekReminders = $0 }))
            GSDivider()
            GSToggleRow(symbol: "timer", title: "Focus round", text: "When an in-app focus round ends.",
                        isOn: Binding(get: { prefs.peekFocusDone }, set: { prefs.peekFocusDone = $0 }))
        }
    }

    private static func title(for minutes: Int) -> String {
        if let index = leadValues.firstIndex(of: minutes) { return leads[index] }
        return "\(minutes) min before"
    }
}
