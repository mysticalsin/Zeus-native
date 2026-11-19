import Foundation

/// Meeting mode mutes Zeus's sounds while another app records (a call). Zeus's own microphone
/// users (wake word, Scribe, Talk to Zeus, a dictation still closing) never count: before this, the
/// device-wide "input is running" flag counted them, so meeting mode muted the dictation cues.
public enum MeetingMicPolicy {
    /// One Core Audio client process and whether it is recording from any input right now.
    public struct InputProcess: Equatable, Sendable {
        public let pid: Int32
        public let recording: Bool

        public init(pid: Int32, recording: Bool) {
            self.pid = pid
            self.recording = recording
        }
    }

    public static func anotherProcessRecords(_ processes: [InputProcess], ownPID: Int32) -> Bool {
        processes.contains { $0.recording && $0.pid != ownPID }
    }
}
