import Foundation
import Testing

// The settings rules live in the Zeus target, which this test target cannot import. These tests pin the
// Foundation behaviour those rules rely on, written the same way the rules read the values.

private func isWhole(_ value: Any, in range: ClosedRange<Int>) -> Bool {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    let double = number.doubleValue
    guard double.isFinite, double == double.rounded(), abs(double) < 1e9 else { return false }
    return range.contains(Int(double))
}

@Suite struct W7SettingsVoiceTests {
    private func parsed(_ json: String) throws -> Any {
        let data = Data("{\"v\": \(json)}".utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object?["v"])
    }

    @Test func foreverRetentionSurvivesAnImport() throws {
        #expect(isWhole(try parsed("0"), in: 0...3650))
        #expect(isWhole(try parsed("30"), in: 0...3650))
        #expect(isWhole(try parsed("3650"), in: 0...3650))
    }

    @Test func fractionsAndOutOfRangeRetentionAreRejected() throws {
        #expect(!isWhole(try parsed("30.5"), in: 0...3650))
        #expect(!isWhole(try parsed("-1"), in: 0...3650))
        #expect(!isWhole(try parsed("3651"), in: 0...3650))
        #expect(!isWhole(try parsed("true"), in: 0...3650))
        #expect(!isWhole(try parsed("\"30\""), in: 0...3650))
    }

    @Test func aWholeNumberWrittenAsADecimalStillCounts() throws {
        #expect(isWhole(try parsed("14.0"), in: 0...3650))
    }
}
