import Foundation
import Testing
@testable import ZeusCore

@Suite("Untrusted Mac action numbers")
struct MacActionNumberTests {
    private func drive(_ fields: [String: JSONValue]) -> DrivePlan? {
        DrivePlan.parse(["steps": .array([.object(fields)])])
    }

    private func tour(_ fields: [String: JSONValue]) -> Walkthrough? {
        Walkthrough.parse(["steps": .array([.object(fields)])])
    }

    @Test func hugeSerializedCoordinatesAreRejectedWithoutAnIntegerTrap() throws {
        let payload = try JSONDecoder().decode([String: JSONValue].self, from: Data(
            #"{"steps":[{"do":"click","say":"Click here","x":1e300,"y":20}]}"#.utf8
        ))
        #expect(DrivePlan.parse(payload) == nil)
        #expect(Walkthrough.parse(payload) == nil)
    }

    @Test func invalidCoordinatesCannotDowngradeTargetedTypingToCurrentFocus() {
        let invalid: [JSONValue] = [.number(.nan), .number(.infinity), .number(-.infinity),
                                    .number(Double(Int.max)), .number(-1e300), .number(10.5),
                                    .string("NaN"), .string("infinity"), .string("not a number"), .null, .bool(true)]
        for value in invalid {
            let target: [String: JSONValue] = ["do": .string("type"), "text": .string("private text"),
                                               "say": .string("Look here"), "x": value, "y": .number(20)]
            #expect(drive(target) == nil)
            #expect(tour(target) == nil)
        }
        #expect(drive(["do": .string("type"), "text": .string("private text"), "x": .number(1)]) == nil)
        #expect(tour(["say": .string("Look here"), "y": .number(1)]) == nil)
    }

    @Test func aMalformedExplicitRefCannotBecomeUntargetedTyping() {
        for value: JSONValue in [.string("invalid"), .string(""), .number(1), .null, .bool(false)] {
            #expect(drive(["do": .string("type"), "text": .string("private text"), "ref": value]) == nil)
            // Even a label fallback must not erase an explicit invalid identity.
            #expect(drive(["do": .string("type"), "text": .string("private text"),
                           "ref": value, "label": .string("Name")]) == nil)
        }
        #expect(drive(["do": .string("type"), "text": .string("hi"), "ref": .string("s3:e4")])?.steps
            == [.type("hi", into: DriveTarget(ref: "s3:e4"))])
        #expect(drive(["do": .string("type"), "text": .string("hi")])?.steps == [.type("hi", into: nil)])
    }

    @Test func signedIntegralCoordinatesAndNumericStringsRemainSupported() throws {
        let fields: [String: JSONValue] = ["do": .string("click"), "say": .string("Look here"),
                                           "x": .number(-1920), "y": .string("1080"), "screen": .number(2)]
        let plan = try #require(drive(fields))
        #expect(plan.steps == [.click(DriveTarget(x: -1920, y: 1080, screen: 2), double: false)])
        let walkthrough = try #require(tour(fields))
        #expect(walkthrough.steps.first?.target == PointTarget(x: -1920, y: 1080, screen: 2))
    }

    @Test func screenNumbersMustBePositiveRepresentableIntegers() {
        for value: JSONValue in [.number(0), .number(-1), .number(1.5), .number(1e300), .string("NaN"), .null] {
            let fields: [String: JSONValue] = ["do": .string("click"), "say": .string("Look here"),
                                               "x": .number(1), "y": .number(2), "screen": value]
            #expect(drive(fields) == nil)
            #expect(tour(fields) == nil)
        }
    }

    @Test func scrollingIsBoundedToTheNativeSigned32BitInput() {
        for value in [Double(Int32.min), Double(Int32.max), -3, 0, 3] {
            #expect(drive(["do": .string("scroll"), "dy": .number(value)])?.steps == [.scroll(Int(value))])
        }
        for value in [Double(Int32.min) - 1, Double(Int32.max) + 1, 1e300, .nan, .infinity, 0.5] {
            #expect(drive(["do": .string("scroll"), "dy": .number(value)]) == nil)
        }
        // An invalid primary field cannot silently fall back to another direction.
        #expect(drive(["do": .string("scroll"), "dy": .string("bad"), "lines": .number(2)]) == nil)
        #expect(drive(["do": .string("scroll")])?.steps == [.scroll(-3)])
    }

    @Test func nonfiniteWaitAndToggleInputsAreRejected() {
        for value: JSONValue in [.number(.nan), .number(.infinity), .string("NaN"), .string("infinity")] {
            #expect(drive(["do": .string("wait"), "seconds": value]) == nil)
            #expect(drive(["do": .string("toggle"), "label": .string("Enabled"), "on": value]) == nil)
        }
        #expect(drive(["do": .string("wait"), "seconds": .number(20)])?.steps == [.wait(5)])
        #expect(drive(["do": .string("wait"), "seconds": .number(-1)])?.steps == [.wait(0)])
    }
}
