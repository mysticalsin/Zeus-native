import Testing
import ZeusCore

@Suite("Warm field insert")
struct WarmFieldInsertTests {
    @Test func firstEmptyFieldSetsTheValue() {
        let steps = WarmFieldInsert.steps(text: "hello", current: "", valueSettable: true,
                                          selectedTextSettable: true, secure: false)
        #expect(steps == [.setValue("hello"), .setSelectedText("hello")])
    }

    @Test func warmFieldInsertsAtTheCaretBeforeRewritingTheValue() {
        let steps = WarmFieldInsert.steps(text: "again", current: "hello", valueSettable: true,
                                          selectedTextSettable: true, secure: false)
        #expect(steps == [.setSelectedText("again"), .setValue("helloagain")])
    }

    @Test func warmFieldStillInsertsWhenTheValueIsNoLongerSettable() {
        let steps = WarmFieldInsert.steps(text: "again", current: "hello", valueSettable: false,
                                          selectedTextSettable: true, secure: false)
        #expect(steps == [.setSelectedText("again")])
    }

    @Test func secureFieldIsNotWritten() {
        let steps = WarmFieldInsert.steps(text: "secret", current: "", valueSettable: true,
                                          selectedTextSettable: true, secure: true)
        #expect(steps.isEmpty)
    }

    @Test func landedRequiresTheWordsInTheField() {
        #expect(WarmFieldInsert.landed(fieldValue: "hello again", selectedText: nil, expected: "again"))
        #expect(!WarmFieldInsert.landed(fieldValue: "hello", selectedText: "", expected: "again"))
    }
}
