import Testing
@testable import ZeusCore

@Suite("Meeting mode microphone check")
struct MeetingMicPolicyTests {
    @Test func zeusRecordingIsNotAMeeting() {
        let own: Int32 = 501
        let zeusOnly = [MeetingMicPolicy.InputProcess(pid: own, recording: true)]
        #expect(MeetingMicPolicy.anotherProcessRecords(zeusOnly, ownPID: own) == false)
        let idleCallApp = zeusOnly + [MeetingMicPolicy.InputProcess(pid: 900, recording: false)]
        #expect(MeetingMicPolicy.anotherProcessRecords(idleCallApp, ownPID: own) == false)
        let liveCall = zeusOnly + [MeetingMicPolicy.InputProcess(pid: 900, recording: true)]
        #expect(MeetingMicPolicy.anotherProcessRecords(liveCall, ownPID: own))
        #expect(MeetingMicPolicy.anotherProcessRecords([], ownPID: own) == false)
    }
}
