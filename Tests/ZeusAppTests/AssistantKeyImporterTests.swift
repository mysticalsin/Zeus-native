import Foundation
import Testing
@testable import Zeus

@Suite struct AssistantKeyImporterTests {
    @Test func neutralKeyFileIsPreferredWhenItExists() {
        let home = "/Users/example"
        let chosen = AssistantKeyImporter.defaultKeyPath(home: home) { path in
            path == home + "/.zeus/anthropic-key.txt"
        }
        #expect(chosen == "/Users/example/.zeus/anthropic-key.txt")
    }

    @Test func legacyKeyFileIsReadWhenTheNeutralFileIsAbsent() {
        let home = "/Users/example"
        let chosen = AssistantKeyImporter.defaultKeyPath(home: home) { path in
            path == home + "/.zeus/tony-anthropic-key.txt"
        }
        #expect(chosen == "/Users/example/.zeus/tony-anthropic-key.txt")
    }

    @Test func bothFilesPresentUsesTheNeutralName() {
        let chosen = AssistantKeyImporter.defaultKeyPath(home: "/Users/example") { _ in true }
        #expect(chosen == "/Users/example/.zeus/anthropic-key.txt")
    }
}
