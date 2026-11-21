import Foundation
import Testing
@testable import ZeusCore

@Suite("Provider engine book")
struct ProviderEngineBookTests {
    @Test func aFinishedWavDropsTheEngineAndTheFile() {
        var book = ProviderEngineBook()
        let file = URL(fileURLWithPath: "/tmp/zeus-voice-one.wav")
        book.started(file)
        #expect(book.engines == 1)
        #expect(book.files == [file])
        #expect(book.finished(file) == file)
        #expect(book.engines == 0)
        #expect(book.files.isEmpty)
        #expect(book.finished(file) == nil)
    }

    @Test func stoppingDropsEveryEngineAndReturnsItsFiles() {
        var book = ProviderEngineBook()
        let first = URL(fileURLWithPath: "/tmp/zeus-voice-a.wav")
        let second = URL(fileURLWithPath: "/tmp/zeus-voice-b.wav")
        book.started(first)
        book.started(second)
        book.finished(first)
        #expect(book.engines == 1)
        #expect(book.files == [second])
        let gone = book.stopAll()
        #expect(gone == [second])
        #expect(book.engines == 0)
        #expect(book.files.isEmpty)
    }
}
