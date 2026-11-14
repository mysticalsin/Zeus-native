import Foundation

// What the meeting-start machine has already done about each meeting, in one place. A calendar meeting is
// remembered by its slot until the slot ends; a call is remembered by its app until the app has not held the
// microphone for a while. Pure: the machine feeds it evidence and reads marks back.

public struct ScribeMeetingLedger: Equatable, Sendable {
    /// How far the machine got with a meeting. Ordered: a mark never goes down.
    public enum Mark: Int, Comparable, Sendable {
        /// The "starts soon" card was shown, or the meeting was offered while another one recorded.
        case headsUp
        /// The question was shown and left unanswered.
        case asked
        /// Not now, or Cancel.
        case declined
        /// Recording began, or was seen.
        case started

        /// A person (or a recording) settled this meeting: nothing more is shown for it.
        public var isAnswered: Bool { self >= .declined }

        public static func < (lhs: Mark, rhs: Mark) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct SlotEntry: Equatable, Sendable {
        var mark: Mark
        var expires: Date
    }

    private struct CallEntry: Equatable, Sendable {
        var mark: Mark
        /// The calendar meeting this call became, once it did.
        var slotID: String?
        /// Since when the app has not held the microphone (machine clock).
        var absentSince: TimeInterval?
    }

    private var slots: [String: SlotEntry] = [:]
    private var calls: [ScribeCallApp: CallEntry] = [:]

    public init() {}

    /// Records `mark` for the meeting. A meeting with a slot gets a slot entry kept until the slot's end; a live
    /// meeting, or a call with no calendar behind it, also gets an entry for its app, tied to that slot.
    public mutating func note(_ meeting: ScribeMeeting, _ mark: Mark, date: Date) {
        if let slot = meeting.slot, Self.expiry(of: slot) > date {
            let kept = slots[slot.id]?.mark ?? mark
            slots[slot.id] = SlotEntry(mark: max(kept, mark), expires: Self.expiry(of: slot))
        }
        guard let app = meeting.callApp, meeting.slot == nil || meeting.isLive else { return }
        var entry = calls[app] ?? CallEntry(mark: mark)
        entry.mark = max(entry.mark, mark)
        if let slot = meeting.slot { entry.slotID = slot.id }
        calls[app] = entry
    }

    /// What is known about the meeting, or nil when nothing is. A call answered before its calendar window
    /// opened has not yet belonged to any slot: a live meeting in that slot inherits the answer, and the next
    /// `note` for the meeting writes it onto the slot.
    public func mark(of meeting: ScribeMeeting) -> Mark? {
        if let slot = meeting.slot {
            if let entry = slots[slot.id] { return entry.mark }
            return meeting.isLive ? adoptableCall(for: meeting)?.mark : nil
        }
        return meeting.callApp.flatMap { calls[$0]?.mark }
    }

    /// The mark of a calendar slot by id, nil when nothing is known.
    public func mark(ofSlot id: String) -> Mark? { slots[id]?.mark }

    /// Reads one piece of evidence: slot entries leave at their end, and a call entry leaves once its app has not
    /// held the microphone for `rearmAfterAbsence`. A native app that is no longer running leaves at once. A
    /// browser call is seen only while its window title says so, so a missing browser call is not proof that the
    /// call ended: it is absent like one that is muted.
    public mutating func observe(_ evidence: ScribeMeetingEvidence, now: TimeInterval,
                                 rearmAfterAbsence: TimeInterval = ScribeAutoStartTiming.standard.rearmAfterAbsence) {
        slots = slots.filter { $0.value.expires > evidence.date }
        for (app, entry) in calls {
            if app != .meet, !evidence.presentApps.contains(app), !evidence.micApps.contains(app) {
                calls[app] = nil
                continue
            }
            var updated = entry
            updated.absentSince = evidence.micApps.contains(app) ? nil : (entry.absentSince ?? now)
            if let since = updated.absentSince, now - since >= rearmAfterAbsence {
                calls[app] = nil
            } else {
                calls[app] = updated
            }
        }
    }

    private func adoptableCall(for meeting: ScribeMeeting) -> CallEntry? {
        guard let app = meeting.callApp, let entry = calls[app], entry.slotID == nil else { return nil }
        return entry
    }

    private static func expiry(of slot: ScribeCalendarSlot) -> Date {
        slot.end ?? slot.start.addingTimeInterval(ScribeMeetingStartPolicy.lateWindow)
    }
}
