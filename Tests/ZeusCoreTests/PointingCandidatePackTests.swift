import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing candidate pack")
struct PointingCandidatePackTests {
    private func rect(_ width: Double = 40, _ height: Double = 18) -> PointingCandidatePack.Rect {
        PointingCandidatePack.Rect(x: 12, y: 40, width: width, height: height)
    }

    private func draft(_ id: String, label: String? = "Share", secure: Bool = false, role: String = "AXButton") -> PointingCandidatePack.Draft {
        PointingCandidatePack.Draft(id: id, role: role, label: label, rect: rect(), isSecure: secure)
    }

    @Test func theDefaultPackNamesOneDisplayAndCarriesNoImageBytes() throws {
        let pack = try #require(PointingCandidatePack(displayID: 7, candidates: [draft("share")]))
        #expect(pack.displayID == 7)
        #expect(pack.sendScreenshot == false)
        #expect(pack.image == nil)
        #expect(pack.carriesImageBytes == false)
        let data = try JSONEncoder().encode(pack)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\"image\""))
        #expect(!text.contains("value"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["displayID"] as? Int == 7)
        #expect(object["sendScreenshot"] as? Bool == false)
        #expect(object["image"] == nil)
    }

    @Test func screenshotOffRefusesImageBytes() {
        let pixels = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(PointingCandidatePack(displayID: 7, sendScreenshot: false, image: pixels, candidates: [draft("share")]) == nil)
    }

    @Test func anEmptyImageIsStoredAsNoBytes() throws {
        let pack = try #require(PointingCandidatePack(displayID: 7, sendScreenshot: false, image: Data(), candidates: []))
        #expect(pack.image == nil)
        #expect(pack.candidates.isEmpty)
        let withConsent = try #require(PointingCandidatePack(displayID: 7, sendScreenshot: true, image: Data(), candidates: []))
        #expect(withConsent.image == nil)
        #expect(withConsent.carriesImageBytes == false)
    }

    @Test func screenshotOnKeepsTheBytesForThatDisplay() throws {
        let pixels = Data([0x01, 0x02, 0x03])
        let pack = try #require(PointingCandidatePack(displayID: 4, sendScreenshot: true, image: pixels, candidates: [draft("share")]))
        #expect(pack.image == pixels)
        #expect(pack.carriesImageBytes == true)
        #expect(pack.displayID == 4)
        let data = try JSONEncoder().encode(pack)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["image"] != nil)
    }

    @Test func anImagePastEightMebibytesIsRefused() {
        let pixels = Data(count: PointingCandidatePack.maxImageBytes + 1)
        #expect(PointingCandidatePack(displayID: 4, sendScreenshot: true, image: pixels, candidates: []) == nil)
    }

    @Test func aSecureControlDropsTheLabelAndStoresNoValue() throws {
        let pack = try #require(PointingCandidatePack(displayID: 7, candidates: [draft("password", label: "hunter2", secure: true)]))
        let control = try #require(pack.candidates.first)
        #expect(control.isSecure == true)
        #expect(control.label == nil)
        #expect(control.role == "AXButton")
        let data = try JSONEncoder().encode(control)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "role", "rect", "isSecure"])
        #expect(object["label"] == nil)
        #expect(object["value"] == nil)
    }

    @Test func aLongLabelIsCutAt128BytesAndASecureLabelIsNotKeptBesideIt() throws {
        let long = String(repeating: "a", count: 129)
        let pack = try #require(PointingCandidatePack(displayID: 7, candidates: [draft("share", label: long)]))
        let label = try #require(pack.candidates.first?.label)
        #expect(label.utf8.count == 128)
        #expect(label == String(repeating: "a", count: 128))
        let marked = String(repeating: "é", count: 64) + "Z"
        let cut = PointingCandidatePack.cut(marked, bytes: 128)
        #expect(cut.utf8.count <= 128)
        #expect(!cut.hasSuffix("Z"))
    }

    @Test func nineControlsAreRefusedAndEightAreKept() throws {
        let eight = (0..<8).map { draft("c\($0)") }
        let pack = try #require(PointingCandidatePack(displayID: 7, candidates: eight))
        #expect(pack.candidates.count == 8)
        let nine = eight + [draft("c8")]
        #expect(PointingCandidatePack(displayID: 7, candidates: nine) == nil)
    }

    @Test func aDuplicateIdABlankRoleOrABadIdIsRefused() {
        #expect(PointingCandidatePack(displayID: 7, candidates: [draft("share"), draft("share")]) == nil)
        #expect(PointingCandidatePack(displayID: 7, candidates: [draft("share", role: "   ")]) == nil)
        #expect(PointingCandidatePack(displayID: 7, candidates: [draft("has space")]) == nil)
        #expect(PointingCandidatePack(displayID: 0, candidates: [draft("share")]) == nil)
    }

    @Test func aFlatOrNonFiniteRectangleIsRefusedAndANegativeOriginIsKept() throws {
        let flat = PointingCandidatePack.Draft(id: "share", role: "AXButton", rect: rect(0, 18))
        #expect(PointingCandidatePack(displayID: 7, candidates: [flat]) == nil)
        let broken = PointingCandidatePack.Draft(
            id: "share", role: "AXButton",
            rect: PointingCandidatePack.Rect(x: .infinity, y: 1, width: 4, height: 4))
        #expect(PointingCandidatePack(displayID: 7, candidates: [broken]) == nil)
        let left = PointingCandidatePack.Draft(
            id: "share", role: "AXButton",
            rect: PointingCandidatePack.Rect(x: -1200, y: 20, width: 40, height: 18))
        let pack = try #require(PointingCandidatePack(displayID: 3, candidates: [left]))
        #expect(pack.candidates.first?.rect.x == -1200)
        #expect(pack.displayID == 3)
    }
}
