import Testing
import ZeusCore

@Suite struct ShippedShortcutDefaultsTests {
    @Test func noTwoDefaultChordsCollide() {
        #expect(ShippedShortcutDefaults.collisions().isEmpty)
    }

    @Test func quickTodoIsNotTheLiveCaptionsChord() {
        #expect(ShippedShortcutDefaults.quickTodo.keyCode == 6)
        #expect(ShippedShortcutDefaults.quickTodo.modifiers == [.control, .command])
        #expect(ShippedShortcutDefaults.polyglot.keyCode == 17)
        #expect(ShippedShortcutDefaults.polyglot.modifiers == [.control, .option])
    }
}
