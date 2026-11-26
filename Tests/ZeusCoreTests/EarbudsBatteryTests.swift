import Testing
@testable import ZeusCore

@Suite("Earbuds battery") struct EarbudsBatteryTests {
    @Test func validRange() {
        #expect(BatteryReading.valid(nil) == nil)
        #expect(BatteryReading.valid(0) == nil)
        #expect(BatteryReading.valid(1) == 1)
        #expect(BatteryReading.valid(100) == 100)
        #expect(BatteryReading.valid(101) == nil)
        #expect(BatteryReading.valid(255) == nil)
        #expect(BatteryReading.valid(-1) == nil)
    }

    @Test func layouts() {
        #expect(EarbudsParts.layout(answering: []) == [])
        #expect(EarbudsParts.layout(answering: [.case]) == [])
        #expect(EarbudsParts.layout(answering: [.left]) == [.left, .right, .case])
        #expect(EarbudsParts.layout(answering: [.right]) == [.left, .right, .case])
        #expect(EarbudsParts.layout(answering: [.left, .right, .case]) == [.left, .right, .case])
        #expect(EarbudsParts.layout(answering: [.single]) == [.single])
        #expect(EarbudsParts.layout(answering: [.single, .case]) == [.single])
        #expect(EarbudsParts.layout(answering: [.left, .single]) == [.left, .right, .case])
    }

    @Test func anInvalidPartKeepsTheOldValue() {
        var book = BatteryBook()
        book.merge([.left: 80], now: 0)
        book.merge([.left: nil, .right: 0], now: 10)
        #expect(book.level(.left, now: 10) == .lastKnown(80))
        #expect(book.level(.right, now: 10) == .unknown)
        #expect(book.level(.case, now: 10) == .unknown)
    }

    @Test func freshThenLastKnownThenUnknownAt1800() {
        var book = BatteryBook()
        book.merge([.left: 50], now: 0)
        #expect(book.level(.left, now: 0) == .fresh(50))
        #expect(book.hasAnyFresh(now: 0))
        #expect(book.level(.left, now: 0.001) == .lastKnown(50))
        #expect(!book.hasAnyFresh(now: 0.001))
        #expect(book.level(.left, now: BatteryBook.lastKnownLifetime - 0.001) == .lastKnown(50))
        #expect(book.level(.left, now: BatteryBook.lastKnownLifetime) == .unknown)
    }

    @Test func noPathYieldsZero() {
        for part in EarbudsPart.allCases {
            for raw in 0 ... 255 {
                var book = BatteryBook()
                book.merge([part: raw], now: 5)
                let level = book.level(part, now: 5)
                #expect(level != .fresh(0))
                #expect(level != .lastKnown(0))
                var kept = BatteryBook()
                kept.merge([part: 40], now: 0)
                kept.merge([part: raw == 40 ? 41 : raw], now: 5)
                let later = kept.level(part, now: 5)
                #expect(later != .fresh(0))
                #expect(later != .lastKnown(0))
            }
        }
    }
}
