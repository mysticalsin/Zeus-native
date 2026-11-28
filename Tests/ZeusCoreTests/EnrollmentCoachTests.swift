import Testing
@testable import ZeusCore

struct EnrollmentCoachTests {
    @Test func aRefusalSaysWhatToChange() {
        #expect(EnrollmentCoach.line(.noFace) == "No face in view. Look at the camera.")
        #expect(EnrollmentCoach.line(.unreadable) == "That frame could not be read. Hold still.")
        #expect(EnrollmentCoach.line(.otherRevision) == "That frame does not match this enrollment.")
        #expect(EnrollmentCoach.line(.spoofed) == "That looks like a photo or a screen. Use your face.")
        #expect(EnrollmentCoach.line(.weakAlignment) == "Move so your whole face is in view.")
        #expect(EnrollmentCoach.line(.lowQuality) == "The picture is too unclear. Face the light.")
        #expect(EnrollmentCoach.line(.tooSimilar) == "Move a little. That frame matched the last one.")
    }

    @Test func progressCountsTowardTen() {
        #expect(EnrollmentCoach.progress(accepted: 3) == "3 of 10.")
        #expect(EnrollmentCoach.progress(accepted: 0) == "0 of 10.")
        #expect(EnrollmentCoach.progress(accepted: -4) == "0 of 10.")
        #expect(EnrollmentCoach.progress(accepted: 40) == "10 of 10.")
    }

    @Test func theLineShowsOnlyWhileEnrolling() {
        #expect(EnrollmentCoach.shown(enrolling: true, line: "3 of 10.") == "3 of 10.")
        #expect(EnrollmentCoach.shown(enrolling: true, line: "  ") == nil)
        #expect(EnrollmentCoach.shown(enrolling: false, line: "3 of 10.") == nil)
        #expect(EnrollmentCoach.shown(enrolling: true, line: nil) == nil)
    }
}
