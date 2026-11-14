import Foundation
import Testing
@testable import ZeusCore

/// Where `zeus debug screenshot` may write. Disposable temp folders only.
@Suite("Debug output path rule")
struct DebugOutputPathTests {
    private func folder() throws -> (root: String, cleanup: () -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-shot-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (url.path, { try? FileManager.default.removeItem(at: url) })
    }

    private func accepted(_ result: Result<String, DebugOutputPath.Rejection>) -> String? {
        if case .success(let path) = result { return path }
        return nil
    }

    private func rejection(_ result: Result<String, DebugOutputPath.Rejection>) -> DebugOutputPath.Rejection? {
        if case .failure(let reason) = result { return reason }
        return nil
    }

    @Test func aFileInsideAnAllowedFolderIsAccepted() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        let accepted = accepted(DebugOutputPath.validate(root + "/shots/one.png", allowedFolders: [root]))
        #expect(accepted?.hasSuffix("/shots/one.png") == true)
    }

    @Test func aFolderThatDoesNotExistYetIsFineWhenItsAncestorIsAllowed() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        #expect(accepted(DebugOutputPath.validate(root + "/a/b/c/shot", allowedFolders: [root])) != nil)
    }

    @Test func anAllowedFolderThatDoesNotExistYetStillWorks() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        let caches = root + "/Library/Caches/app.zeus.mac"
        #expect(accepted(DebugOutputPath.validate(caches + "/shot", allowedFolders: [caches])) != nil)
    }

    @Test func anythingOutsideTheAllowedFoldersIsRefused() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        #expect(rejection(DebugOutputPath.validate("/tmp/evil", allowedFolders: [root])) == .outsideAllowedFolders)
        #expect(rejection(DebugOutputPath.validate("/etc/passwd", allowedFolders: [root])) == .outsideAllowedFolders)
        #expect(rejection(DebugOutputPath.validate(root + "-sibling/x", allowedFolders: [root])) == .outsideAllowedFolders, "a sibling that shares the prefix")
        #expect(rejection(DebugOutputPath.validate(root, allowedFolders: [root])) == .outsideAllowedFolders, "the folder itself is not a file inside it")
        #expect(rejection(DebugOutputPath.validate(root + "/x", allowedFolders: [])) == .outsideAllowedFolders, "no allowed folder, no output")
    }

    @Test func traversalIsRefusedBeforeAnythingIsResolved() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        #expect(rejection(DebugOutputPath.validate(root + "/../escape", allowedFolders: [root])) == .traversal)
        #expect(rejection(DebugOutputPath.validate(root + "/a/../../escape", allowedFolders: [root])) == .traversal)
        #expect(rejection(DebugOutputPath.validate(root + "/x\u{0}/y", allowedFolders: [root])) == .traversal)
    }

    @Test func relativeAndEmptyPathsAreRefused() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        #expect(rejection(DebugOutputPath.validate("shot", allowedFolders: [root])) == .notAbsolute)
        #expect(rejection(DebugOutputPath.validate("./shot", allowedFolders: [root])) == .notAbsolute)
        #expect(rejection(DebugOutputPath.validate("   ", allowedFolders: [root])) == .empty)
        #expect(rejection(DebugOutputPath.validate("", allowedFolders: [root])) == .empty)
    }

    @Test func aSymlinkedFolderCannotCarryTheOutputOutside() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        let (outside, outsideCleanup) = try folder()
        defer { outsideCleanup() }
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: outside)
        #expect(rejection(DebugOutputPath.validate(root + "/link/shot", allowedFolders: [root])) == .outsideAllowedFolders)
        #expect(rejection(DebugOutputPath.validate(root + "/link/deeper/shot", allowedFolders: [root])) == .outsideAllowedFolders)
    }

    @Test func aSymlinkAsTheFinalNameCannotCarryTheOutputOutside() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        let (outside, outsideCleanup) = try folder()
        defer { outsideCleanup() }
        let target = outside + "/victim.png"
        FileManager.default.createFile(atPath: target, contents: Data("x".utf8))
        try FileManager.default.createSymbolicLink(atPath: root + "/shot.png", withDestinationPath: target)
        #expect(rejection(DebugOutputPath.validate(root + "/shot.png", allowedFolders: [root])) == .outsideAllowedFolders)
    }

    @Test func aSymlinkThatStaysInsideIsAccepted() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        try FileManager.default.createDirectory(atPath: root + "/real", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/alias", withDestinationPath: root + "/real")
        let result = accepted(DebugOutputPath.validate(root + "/alias/shot", allowedFolders: [root]))
        #expect(result?.hasSuffix("/real/shot") == true, "the returned path is the resolved one")
    }

    @Test func aSymlinkedAllowedFolderIsResolvedToo() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        try FileManager.default.createDirectory(atPath: root + "/real", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/allowed", withDestinationPath: root + "/real")
        #expect(accepted(DebugOutputPath.validate(root + "/real/shot", allowedFolders: [root + "/allowed"])) != nil)
        #expect(rejection(DebugOutputPath.validate(root + "/other/shot", allowedFolders: [root + "/allowed"])) == .outsideAllowedFolders)
    }

    @Test func tildeIsExpandedBeforeTheCheck() {
        let home = NSHomeDirectory()
        #expect(rejection(DebugOutputPath.validate("~/Desktop/shot", allowedFolders: [home + "/Library/Caches/app.zeus.mac"])) == .outsideAllowedFolders)
        #expect(accepted(DebugOutputPath.validate("~/Library/Caches/app.zeus.mac/shot", allowedFolders: [home + "/Library/Caches/app.zeus.mac"])) != nil)
    }

    // MARK: Which folders are allowed

    @Test func theAppCachesFolderIsAlwaysAllowed() {
        let folders = DebugOutputPath.allowedFolders(cachesDirectory: "/Users/me/Library/Caches", environment: [:])
        #expect(folders == ["/Users/me/Library/Caches/app.zeus.mac"])
    }

    @Test func theOwnerCanChooseOneMoreFolderAtLaunch() {
        let folders = DebugOutputPath.allowedFolders(cachesDirectory: "/Users/me/Library/Caches",
                                                     environment: ["ZEUS_DEBUG_SCREENSHOT_DIR": "/Users/me/qa-shots"])
        #expect(folders == ["/Users/me/Library/Caches/app.zeus.mac", "/Users/me/qa-shots"])
    }

    @Test func aChosenFolderThatIsRelativeOrBroadIsIgnored() {
        for bad in ["", "relative/dir", "/", "/Users/me/../other", "~/shots"] {
            let folders = DebugOutputPath.allowedFolders(cachesDirectory: "/Users/me/Library/Caches",
                                                         environment: ["ZEUS_DEBUG_SCREENSHOT_DIR": bad])
            #expect(folders == ["/Users/me/Library/Caches/app.zeus.mac"], "\(bad)")
        }
    }

    @Test func aChosenFolderThatReachesTheHomeFolderOrStartupFilesIsIgnored() {
        let caches = ["/Users/me/Library/Caches/app.zeus.mac"]
        let broad = ["/Users/me", "/Users/me/", "/Users", "/Users/me/Library", "/Users/me/Library/LaunchAgents",
                     "/Users/me/Library/LaunchAgents/sub", "/Users/me/.ssh", "/Users/me/.config/zeus"]
        for bad in broad {
            let folders = DebugOutputPath.allowedFolders(cachesDirectory: "/Users/me/Library/Caches",
                                                         environment: ["ZEUS_DEBUG_SCREENSHOT_DIR": bad], homeDirectory: "/Users/me")
            #expect(folders == caches, "\(bad)")
        }
    }

    @Test func aFolderBelowTheHomeFolderIsStillAllowed() {
        for good in ["/Users/me/Documents/shots", "/Users/me/qa-shots", "/Users/me/Library/Caches/shots", "/Volumes/Work/shots"] {
            let folders = DebugOutputPath.allowedFolders(cachesDirectory: "/Users/me/Library/Caches",
                                                         environment: ["ZEUS_DEBUG_SCREENSHOT_DIR": good], homeDirectory: "/Users/me")
            #expect(folders.contains(good), "\(good)")
        }
    }

    @Test func aChosenFolderThatIsALinkToTheHomeFolderIsIgnored() throws {
        let (root, cleanup) = try folder()
        defer { cleanup() }
        try FileManager.default.createDirectory(atPath: root + "/home/Library", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/shots", withDestinationPath: root + "/home")
        try FileManager.default.createSymbolicLink(atPath: root + "/lib", withDestinationPath: root + "/home/Library")
        for link in ["/shots", "/lib"] {
            let folders = DebugOutputPath.allowedFolders(cachesDirectory: root + "/caches",
                                                         environment: ["ZEUS_DEBUG_SCREENSHOT_DIR": root + link], homeDirectory: root + "/home")
            #expect(folders.count == 1, "\(link)")
        }
    }

    @Test func theDefaultBaseLivesInTheCachesFolder() {
        let base = DebugOutputPath.defaultBase(cachesDirectory: "/Users/me/Library/Caches", token: "abc")
        #expect(base == "/Users/me/Library/Caches/app.zeus.mac/DebugScreenshots/zeus-screenshot-abc")
    }
}
