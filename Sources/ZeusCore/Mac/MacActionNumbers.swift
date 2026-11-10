import Foundation

/// Numeric fields in model/tool payloads are untrusted. Convert only finite, exactly representable
/// integers: `Int(Double)` traps on overflow/NaN and silently truncates fractional coordinates.
enum MacActionNumbers {
    static func integer(_ value: JSONValue) -> Int? {
        guard let number = value.numberValue, number.isFinite else { return nil }
        return Int(exactly: number)
    }

    static func screen(_ value: JSONValue) -> Int? {
        guard let number = integer(value), number > 0 else { return nil }
        return number
    }

    static func scrollLines(_ value: JSONValue) -> Int? {
        guard let number = integer(value), Int32(exactly: number) != nil else { return nil }
        return number
    }
}
