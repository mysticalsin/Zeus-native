import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly capture source box")
struct RecordlyCaptureSourceBoxTests {
    private func encode(_ stored: RecordlyCaptureSourceBox.Stored) throws -> [String: Any] {
        let data = try JSONEncoder().encode(Envelope(stored))
        let value = try JSONSerialization.jsonObject(with: data)
        return value as? [String: Any] ?? [:]
    }

    private func decode(_ json: String) throws -> RecordlyCaptureSourceBox.Stored {
        try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).stored
    }

    private func number(_ object: [String: Any], _ key: String) -> Double? {
        (object[key] as? NSNumber)?.doubleValue
    }

    @Test func displayReadsDisplayAndAZeroRegion() {
        let stored = RecordlyCaptureSourceBox.Stored.display(id: 4)
        #expect(RecordlyCaptureSourceBox.kind(of: stored) == .display)
        #expect(RecordlyCaptureSourceBox.region(of: stored) == .zero)
    }

    @Test func windowReadsWindowAndAZeroRegion() {
        let stored = RecordlyCaptureSourceBox.Stored.window(number: 9)
        #expect(RecordlyCaptureSourceBox.kind(of: stored) == .window)
        #expect(RecordlyCaptureSourceBox.region(of: stored) == .zero)
    }

    @Test func regionReadsRegionAndItsEdges() {
        let stored = RecordlyCaptureSourceBox.Stored.region(x: 8, y: 16, width: 32, height: 64)
        #expect(RecordlyCaptureSourceBox.kind(of: stored) == .region)
        #expect(RecordlyCaptureSourceBox.region(of: stored) == RecordlyCaptureSourceBox.Region(x: 8, y: 16, width: 32, height: 64))
    }

    @Test func negativeEdgesStayNegative() {
        let stored = RecordlyCaptureSourceBox.Stored.region(x: -3, y: -4, width: -5, height: -6)
        #expect(RecordlyCaptureSourceBox.region(of: stored) == RecordlyCaptureSourceBox.Region(x: -3, y: -4, width: -5, height: -6))
    }

    @Test func zeroSizeRegionIsStillARegion() {
        let stored = RecordlyCaptureSourceBox.Stored.region(x: 1, y: 2, width: 0, height: 0)
        #expect(RecordlyCaptureSourceBox.kind(of: stored) == .region)
        #expect(RecordlyCaptureSourceBox.region(of: stored) == RecordlyCaptureSourceBox.Region(x: 1, y: 2, width: 0, height: 0))
    }

    @Test func factoryStoresTheGivenEdges() {
        #expect(RecordlyCaptureSourceBox.region(x: 1.5, y: 2.25, width: 3.5, height: 4.75) ==
            RecordlyCaptureSourceBox.Region(x: 1.5, y: 2.25, width: 3.5, height: 4.75))
    }

    @Test func nonFiniteWidthIsStored() {
        let region = RecordlyCaptureSourceBox.region(x: 1, y: 2, width: .nan, height: 4)
        #expect(region.x == 1)
        #expect(region.y == 2)
        #expect(region.width.isNaN)
        #expect(region.height == 4)
        #expect(RecordlyCaptureSourceBox.region(of: .region(x: 1, y: 2, width: .infinity, height: 4)).width.isInfinite)
    }

    @Test func displayEncodesKindAndId() throws {
        let object = try encode(.display(id: 7))
        #expect(object["kind"] as? String == "display")
        #expect(number(object, "id") == 7)
        #expect(Set(object.keys) == ["kind", "id"])
    }

    @Test func windowEncodesKindAndNumber() throws {
        let object = try encode(.window(number: -12))
        #expect(object["kind"] as? String == "window")
        #expect(number(object, "number") == -12)
        #expect(Set(object.keys) == ["kind", "number"])
    }

    @Test func regionEncodesEveryEdge() throws {
        let object = try encode(.region(x: 1, y: -2, width: 3.5, height: 4))
        #expect(object["kind"] as? String == "region")
        #expect(number(object, "x") == 1)
        #expect(number(object, "y") == -2)
        #expect(number(object, "width") == 3.5)
        #expect(number(object, "height") == 4)
        #expect(Set(object.keys) == ["kind", "x", "y", "width", "height"])
    }

    @Test func displayDecodes() throws {
        #expect(try decode(#"{"kind":"display","id":0}"#) == .display(id: 0))
    }

    @Test func windowDecodes() throws {
        #expect(try decode(#"{"kind":"window","number":-8}"#) == .window(number: -8))
    }

    @Test func regionDecodes() throws {
        #expect(try decode(#"{"kind":"region","x":1.5,"y":2,"width":3,"height":4.25}"#) ==
            .region(x: 1.5, y: 2, width: 3, height: 4.25))
    }

    @Test func unknownKindIsRefused() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"screen","id":1}"#)
        }
    }

    @Test func missingRegionHeightIsRefused() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"region","x":1,"y":2,"width":3}"#)
        }
    }
}

private struct Envelope: Codable {
    var stored: RecordlyCaptureSourceBox.Stored

    init(_ stored: RecordlyCaptureSourceBox.Stored) {
        self.stored = stored
    }

    init(from decoder: Decoder) throws {
        stored = try RecordlyCaptureSourceBox.decode(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try RecordlyCaptureSourceBox.encode(stored, to: encoder)
    }
}
