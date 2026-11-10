import Foundation
import Testing
@testable import ZeusCore

@Suite struct ProjectIndexTests {
    private let index = ProjectIndex([
        ProjectEntry(name: "zeus", path: "/Users/t/dev/zeus"),
        ProjectEntry(name: "zeus-site", path: "/Users/t/dev/zeus-site"),
        ProjectEntry(name: "Polyglot", path: "/Users/t/Documents/Polyglot"),
        ProjectEntry(name: "metis-backup", path: "/Users/t/Developer/metis-backup"),
        ProjectEntry(name: "PolyglotApp", path: "/Users/t/Projects/PolyglotApp"),
        ProjectEntry(name: "loop-swap", path: "/Users/t/Developer/loop-swap"),
    ])

    private func name(_ query: String) -> String? {
        if case .project(let entry) = index.lookup(query) { return entry.name }
        return nil
    }

    @Test func exactNamesMatchWithFullConfidence() {
        #expect(index.best("zeus")?.entry.path == "/Users/t/dev/zeus")
        #expect(index.best("zeus")?.score == 1)
        #expect(name("polyglot") == "Polyglot")
        #expect(name("Polyglot") == "Polyglot")
    }

    @Test func spokenFormsOfSeparatedNames() {
        #expect(name("zeus site") == "zeus-site")
        #expect(name("metis backup") == "metis-backup")
        #expect(name("metis") == "metis-backup")
        #expect(name("loop swap") == "loop-swap")
        #expect(name("polyglot app") == "PolyglotApp")
    }

    @Test func smallMishearingsStillMatch() {
        let single = ProjectIndex([ProjectEntry(name: "Polyglot", path: "/p/Polyglot"), ProjectEntry(name: "metis-backup", path: "/p/metis-backup")])
        if case .project(let entry) = single.lookup("polygot") { #expect(entry.name == "Polyglot") } else { Issue.record("polygot not matched") }
        if case .project(let entry) = single.lookup("metis backap") { #expect(entry.name == "metis-backup") } else { Issue.record("metis backap not matched") }
        // two projects both called polyglot-something make a mishearing ambiguous, not a guess
        if case .project = index.lookup("polygot") { Issue.record("expected no confident match") }
    }

    @Test func unknownNamesAreNotGuessed() {
        #expect(name("spotify") == nil)
        #expect(name("banana") == nil)
        #expect(name("") == nil)
        #expect(index.confident("kubernetes") == nil)
    }

    @Test func userAliasesPointAtAProject() {
        let aliased = ProjectIndex(index.entries, userAliases: ["languages": "/Users/t/Documents/Polyglot", "ghost": "/nowhere"])
        if case .project(let entry) = aliased.lookup("languages") { #expect(entry.name == "Polyglot") } else { Issue.record("alias not found") }
        if case .none = aliased.lookup("ghost") {} else { Issue.record("alias to an unknown path must not match") }
    }

    @Test func twoCloseProjectsAreAmbiguous() {
        let twins = ProjectIndex([ProjectEntry(name: "api-server", path: "/a/api-server"), ProjectEntry(name: "api-service", path: "/a/api-service")])
        if case .ambiguous = twins.lookup("api ser") {} else { Issue.record("expected ambiguous, got \(twins.lookup("api ser"))") }
    }

    @Test func tildePath() {
        #expect(ProjectIndex.tilde("/Users/t/dev/zeus", home: "/Users/t") == "~/dev/zeus")
        #expect(ProjectIndex.tilde("/Users/t", home: "/Users/t") == "~")
        #expect(ProjectIndex.tilde("/opt/x", home: "/Users/t") == "/opt/x")
    }

    // MARK: Scanning (a temp folder tree)

    private func makeTree(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-projects-\(UUID().uuidString)")
        for path in paths { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        return root
    }

    @Test func scanFindsReposUpToDepthThreeAndSkipsNoise() throws {
        let root = try makeTree([
            "zeus/.git", "a/b/deep/.git", "a/b/c/toodeep/.git", "node_modules/pkg/.git", "app/.build/x/.git",
            "Library/thing/.git", "plain/notes", "work/client/api/.git", ".hidden/secret/.git",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = ProjectIndex.scan(roots: [root]).map(\.name)
        #expect(found.contains("zeus"))
        #expect(found.contains("deep"))
        #expect(found.contains("api"))
        #expect(!found.contains("toodeep"))
        #expect(!found.contains("pkg"))
        #expect(!found.contains("x"))
        #expect(!found.contains("thing"))
        #expect(!found.contains("secret"))
        #expect(!found.contains("plain"))
    }

    @Test func scanDoesNotLookInsideARepoAndAcceptsWorktreeGitFiles() throws {
        let root = try makeTree(["outer/.git", "outer/packages/inner/.git", "tree"])
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("gitdir: /elsewhere".utf8).write(to: root.appendingPathComponent("tree/.git"))
        let found = ProjectIndex.scan(roots: [root]).map(\.name)
        #expect(found.sorted() == ["outer", "tree"])
    }

    @Test func scanMissingRootsAndStableOrder() throws {
        let root = try makeTree(["b/.git", "a/.git"])
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("nope")
        #expect(ProjectIndex.scan(roots: [missing]).isEmpty)
        #expect(ProjectIndex.scan(roots: [missing, root]).map(\.name) == ["a", "b"])
    }
}
