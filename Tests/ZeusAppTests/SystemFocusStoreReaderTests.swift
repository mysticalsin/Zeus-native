import Foundation
import Testing
@testable import Zeus
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Step zero focus reader")
struct SystemFocusStoreReaderTests {
    private let reader = SystemFocusStoreReader.self

    @Test func errnoClasses() {
        #expect(reader.classify(errno: EPERM) == .denied)
        #expect(reader.classify(errno: EACCES) == .denied)
        #expect(reader.classify(errno: ENOENT) == .missing)
        #expect(reader.classify(errno: ELOOP) == .notAFile)
        #expect(reader.classify(errno: ENOTDIR) == .notAFile)
        #expect(reader.classify(errno: EIO) == .other)
        #expect(reader.classify(errno: 0) == .other)
    }

    @Test func folderJoinsTheLibraryPathAndRefusesABrokenHome() {
        let home = "/tmp/zeus-focus-home"
        let built = reader.folder(home: home)
        #expect(built == home + "/Library/" + reader.storeDirectory + "/" + reader.storeLeaf)
        #expect(reader.folder(home: home + "/") == built)
        #expect(reader.folder(home: "/") == "/Library/" + reader.storeDirectory + "/" + reader.storeLeaf)
        #expect(reader.folder(home: "") == nil)
        #expect(reader.folder(home: "bad\nhome") == nil)
        #expect(reader.folder(home: "bad\0home") == nil)
        let live = reader.liveFolder()
        if let live {
            #expect(live.hasPrefix("/"))
            #expect(live.contains("\0") == false)
        }
    }

    @Test func twoFilesComeBackAndASecondReadStartsAgain() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        try box.write(reader.assertionsFileName, Data("left".utf8))
        try box.write(reader.configurationsFileName, Data("right".utf8))
        try box.write("notes.txt", Data("Secret".utf8))
        let first = reader.read(folder: box.path)
        guard case .opened(let assertions, let configurations, let stamps) = first else {
            Issue.record("expected an open")
            return
        }
        #expect(assertions == .bytes(Data("left".utf8)))
        #expect(configurations == .bytes(Data("right".utf8)))
        #expect(stamps.assertions != nil)
        #expect(stamps.configurations != nil)
        let second = reader.read(folder: box.path)
        #expect(second == first)
        let secret = Data("Secret".utf8)
        #expect(assertions != .bytes(secret))
        #expect(configurations != .bytes(secret))
    }

    @Test func aMissingFolderAndAMissingAssertionsFileStayApart() throws {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-focus-absent-\(UUID().uuidString)").path
        #expect(reader.read(folder: absent) == .folder(.missing))
        #expect(reader.read(folder: "") == .folder(.other))
        #expect(reader.read(folder: "bad\0path") == .folder(.other))
        let box = try Scratch()
        defer { box.cleanup() }
        let opened = reader.read(folder: box.path)
        guard case .opened(let assertions, let configurations, let stamps) = opened else {
            Issue.record("expected an open of an empty folder")
            return
        }
        #expect(assertions == .missing)
        #expect(configurations == .missing)
        #expect(stamps.assertions == nil)
        #expect(stamps.configurations == nil)
    }

    @Test func aSymlinkIsNotAFile() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        let target = box.url.appendingPathComponent("real.txt")
        try Data("body".utf8).write(to: target)
        let link = box.url.appendingPathComponent(reader.assertionsFileName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try box.write(reader.configurationsFileName, Data("cfg".utf8))
        let opened = reader.read(folder: box.path)
        guard case .opened(let assertions, let configurations, _) = opened else {
            Issue.record("expected an open")
            return
        }
        #expect(assertions == .notAFile)
        #expect(configurations == .bytes(Data("cfg".utf8)))
        let alias = box.url.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: box.url)
        #expect(reader.read(folder: alias.path) == .folder(.notAFile))
    }

    @Test func aPipeAndADirectoryAreNotFiles() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        let pipe = box.url.appendingPathComponent(reader.assertionsFileName).path
        #expect(mkfifo(pipe, mode_t(0o644)) == 0)
        try box.write(reader.configurationsFileName, Data("cfg".utf8))
        let opened = reader.read(folder: box.path)
        guard case .opened(let assertions, let configurations, _) = opened else {
            Issue.record("expected an open")
            return
        }
        #expect(assertions == .notAFile)
        #expect(configurations == .bytes(Data("cfg".utf8)))
        let asFolder = reader.read(folder: box.url.appendingPathComponent(reader.configurationsFileName).path)
        #expect(asFolder == .folder(.notAFile))
    }

    @Test func aClosedFolderAndAClosedFileAreDenied() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        #expect(chmod(box.path, 0o000) == 0)
        #expect(reader.read(folder: box.path) == .folder(.denied))
        #expect(chmod(box.path, 0o755) == 0)
        try box.write(reader.assertionsFileName, Data("hidden".utf8))
        #expect(chmod(box.url.appendingPathComponent(reader.assertionsFileName).path, 0o000) == 0)
        let opened = reader.read(folder: box.path)
        guard case .opened(let assertions, let configurations, _) = opened else {
            Issue.record("expected an open")
            return
        }
        #expect(assertions == .denied)
        #expect(configurations == .missing)
        #expect(chmod(box.url.appendingPathComponent(reader.assertionsFileName).path, 0o644) == 0)
    }

    @Test func theCapKeepsFourMegabytesAndDropsOneMoreByte() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        try box.write(reader.assertionsFileName, Data(count: reader.maxBytes))
        try box.write(reader.configurationsFileName, Data("ok".utf8))
        let kept = reader.read(folder: box.path)
        guard case .opened(let assertions, let configurations, _) = kept else {
            Issue.record("expected an open")
            return
        }
        #expect(assertions == .bytes(Data(count: reader.maxBytes)))
        #expect(configurations == .bytes(Data("ok".utf8)))
        try box.write(reader.assertionsFileName, Data(count: reader.maxBytes + 1))
        let dropped = reader.read(folder: box.path)
        guard case .opened(let tooBig, let stillThere, _) = dropped else {
            Issue.record("expected an open")
            return
        }
        #expect(tooBig == .tooLarge)
        #expect(stillThere == .bytes(Data("ok".utf8)))
    }

    @Test func equalStampsSkipTheReadAndARewriteIsRead() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        let assertions = box.url.appendingPathComponent(reader.assertionsFileName)
        try Data("aaaa".utf8).write(to: assertions)
        try box.touch(assertions, seconds: 1_700_000_000)
        let first = reader.read(folder: box.path)
        guard case .opened(let body, _, let stamps) = first else {
            Issue.record("expected an open")
            return
        }
        #expect(body == .bytes(Data("aaaa".utf8)))
        #expect(chmod(assertions.path, 0o000) == 0)
        #expect(reader.read(folder: box.path, ifChangedFrom: stamps) == .unchanged(stamps))
        #expect(chmod(assertions.path, 0o644) == 0)
        try Data("bbbb".utf8).write(to: assertions)
        try box.touch(assertions, seconds: 1_700_000_050)
        let again = reader.read(folder: box.path, ifChangedFrom: stamps)
        guard case .opened(let rewritten, _, let next) = again else {
            Issue.record("expected a fresh open")
            return
        }
        #expect(rewritten == .bytes(Data("bbbb".utf8)))
        #expect(next != stamps)
        #expect(reader.read(folder: box.path, ifChangedFrom: next) == .unchanged(next))
    }

    @Test func oneByteChunksReturnTheWholeFile() throws {
        let box = try Scratch()
        defer { box.cleanup() }
        try box.write(reader.assertionsFileName, Data("abcde".utf8))
        let opened = reader.read(folder: box.path, chunkBytes: 1)
        guard case .opened(let assertions, let configurations, _) = opened else {
            Issue.record("expected an open")
            return
        }
        #expect(assertions == .bytes(Data("abcde".utf8)))
        #expect(configurations == .missing)
        let zero = reader.read(folder: box.path, chunkBytes: 0)
        guard case .opened(let same, _, _) = zero else {
            Issue.record("expected an open")
            return
        }
        #expect(same == .bytes(Data("abcde".utf8)))
    }
}

private struct ReaderCheckError: Error {}

private struct Scratch {
    let url: URL
    var path: String { url.path }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-focus-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ name: String, _ data: Data) throws {
        try data.write(to: url.appendingPathComponent(name))
    }

    func touch(_ file: URL, seconds: Int) throws {
        var times = [
            timespec(tv_sec: time_t(seconds), tv_nsec: 0),
            timespec(tv_sec: time_t(seconds), tv_nsec: 0),
        ]
        let result = times.withUnsafeMutableBufferPointer { buffer in
            file.path.withCString { utimensat(AT_FDCWD, $0, buffer.baseAddress, 0) }
        }
        if result != 0 { throw ReaderCheckError() }
    }

    func cleanup() {
        _ = chmod(path, 0o755)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for name in names {
                _ = chmod(url.appendingPathComponent(name).path, 0o644)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}
