import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly export evidence")
struct RecordlyExportValidationTests {
    @Test func bytesAloneDoNotProveAVideoOrDuration() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("recordly-invalid-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 0, count: 2048).write(to: file)
        let report = await RecordlyExportValidator.validate(url: file, expectedMinDuration: 5)
        #expect(!report.ok)
        #expect(report.durationSeconds == nil)
        #expect(!report.zoomFramesDiffer)
        #expect(report.byteCount == 2048)
    }

    @Test func missingRecordingCannotPass() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("recordly-missing-\(UUID().uuidString).mp4")
        let report = await RecordlyExportValidator.validate(url: file, expectedMinDuration: 5)
        #expect(!report.ok)
        #expect(report.durationSeconds == nil)
    }
}
