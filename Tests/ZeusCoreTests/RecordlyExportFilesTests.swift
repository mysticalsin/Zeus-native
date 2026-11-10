import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly export publication")
struct RecordlyExportFilesTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func concurrentExportsNeverOverwriteEachOther() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let temp = folder.appendingPathComponent(".part-\(index)")
                    try Data("export-\(index)".utf8).write(to: temp)
                    return try RecordlyExportFiles.publish(temp: temp, directory: folder, date: stamp, fileExtension: "mp4")
                }
            }
            var values: [URL] = []
            for try await url in group { values.append(url) }
            return values
        }
        #expect(Set(urls).count == 12)
        let contents = try urls.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(Set(contents) == Set((0..<12).map { "export-\($0)" }))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 12)
    }

    @Test func cancellationBeforePublicationKeepsTempAndExistingExport() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = folder.appendingPathComponent(RecordlyExportPlan.fileName(date: stamp, fileExtension: "mp4"))
        try Data("previous".utf8).write(to: existing)
        let temp = folder.appendingPathComponent(".part")
        try Data("new".utf8).write(to: temp)
        var checks = 0
        #expect(throws: CancellationError.self) {
            try RecordlyExportFiles.publish(temp: temp, directory: folder, date: stamp, fileExtension: "mp4") {
                checks += 1
                if checks == 2 { throw CancellationError() }
            }
        }
        #expect(checks == 2)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "previous")
        #expect(try String(contentsOf: temp, encoding: .utf8) == "new")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }
}
