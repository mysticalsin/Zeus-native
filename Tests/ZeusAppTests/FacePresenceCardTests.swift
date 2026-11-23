import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The card's model and fixtures: what each row shows for each machine state. No view is drawn here.
@Suite("Face presence card")
struct FacePresenceCardTests {
    typealias Machine = FacePresenceMachine

    static func machine(_ events: [Machine.Event]) -> Machine {
        var machine = Machine()
        for event in events { _ = machine.handle(event) }
        return machine
    }

    static let on: Machine.Event = .switchOn(camera: .authorized, enabledFaces: 1, canLock: true, vaultReadable: true, uptime: 100)

    static func record(_ id: String, enabled: Bool = true) -> FaceRecord {
        FaceRecord(id: id, name: "Face \(id)", isEnabled: enabled, revision: 2, samples: [[1, 0, 0], [0, 1, 0]], threshold: 0.3)
    }

    static func model(_ machine: Machine, faces: [FaceRecord] = [], label: String = "2 minutes", uptime: Double = 100) -> FacePresenceCardModel {
        FacePresenceCardModel.make(machine: machine, faces: faces, lockAfterLabel: label, uptime: uptime)
    }

    @Test func enrollIsDisabledOutsideWatchingPresentAndAway() {
        let states: [(String, Machine, Bool)] = [
            ("off", Machine(), false),
            ("needs camera", Self.machine([.switchOn(camera: .notDetermined, enabledFaces: 1, canLock: true, vaultReadable: true, uptime: 1)]), false),
            ("confirm enroll", Self.machine([.switchOn(camera: .authorized, enabledFaces: 0, canLock: true, vaultReadable: true, uptime: 1)]), true),
            ("enrolling", Self.machine([.switchOn(camera: .authorized, enabledFaces: 0, canLock: true, vaultReadable: true, uptime: 1), .enroll]), false),
            ("watching", Self.machine([Self.on]), true),
            ("present", Self.machine([Self.on, .observed(.owner, uptime: 101)]), true),
            ("away", Self.machine([Self.on, .observed(.notOwner, uptime: 101)]), true),
            ("locked", Self.machine([Self.on, .screenLocked]), false),
            ("paused for launch", Self.machine([.launch(storedOn: true)]), false),
            ("no face", Self.machine([Self.on, .facesChanged(enabledFaces: 0, uptime: 102)]), false),
            ("unavailable", Self.machine([.switchOn(camera: .authorized, enabledFaces: 1, canLock: false, vaultReadable: true, uptime: 1)]), false),
        ]
        for (label, machine, expected) in states {
            #expect(Self.model(machine).enrollEnabled == expected, "\(label)")
        }
    }

    /// QA m8: "Lock after absent for" stayed live while Face presence was Off.
    @Test func theLockTimeIsOnlyChangeableWhileFacePresenceIsOn() {
        #expect(!Self.model(Machine()).lockAfterEnabled)
        #expect(Self.model(Self.machine([Self.on])).lockAfterEnabled)
        #expect(Self.model(Self.machine([.switchOn(camera: .notDetermined, enabledFaces: 1, canLock: true, vaultReadable: true, uptime: 1)])).lockAfterEnabled)
    }

    @Test func statusRowNamesTheCountdownForVoiceOver() {
        // Away since 100, two minutes: 18 seconds in, 1:42 left.
        let away = Self.machine([Self.on, .observed(.notOwner, uptime: 101)])
        let model = Self.model(away, uptime: 118)
        #expect(model.status.word == "Away 1:42")
        #expect(model.status.symbol == "person.crop.circle.badge.clock")
        #expect(model.statusAccessibilityLabel == "Face presence status: Away, 1 minute 42 seconds left")
        // Every other state reads its word the same way, and never with a countdown.
        let watching = Self.model(Self.machine([Self.on]))
        #expect(watching.statusAccessibilityLabel == "Face presence status: Watching")
        #expect(watching.status.countdown == nil)
    }

    @Test func theLockChoiceFollowsTheMachinesLimitAndFallsBackToTwoMinutes() {
        #expect(Self.model(Machine(), label: "5 minutes").lockAfterLabel == "5 minutes")
        #expect(Self.model(Machine(), label: "an hour").lockAfterLabel == "2 minutes")
        #expect(Self.model(Machine(), label: "").lockAfterLabel == "2 minutes")
        #expect(FacePresenceCardModel.lockAfterChoices == ["30 seconds", "1 minute", "2 minutes", "5 minutes", "10 minutes"])
    }

    @Test func oneRowPerEnrolledFaceInOrderWithItsSwitchState() {
        let faces = [Self.record("1"), Self.record("2", enabled: false), Self.record("3")]
        let rows = Self.model(Self.machine([Self.on]), faces: faces).faces
        #expect(rows.map(\.id) == ["1", "2", "3"])
        #expect(rows.map(\.name) == ["Face 1", "Face 2", "Face 3"])
        #expect(rows.map(\.isEnabled) == [true, false, true])
        #expect(Self.model(Machine()).faces.isEmpty)
    }

    @Test func theModelHoldsNoFaceDataButNamesAndSwitches() {
        let model = Self.model(Self.machine([Self.on]), faces: [Self.record("1")])
        let labels = Mirror(reflecting: model.faces[0]).children.compactMap(\.label)
        #expect(Set(labels) == ["id", "name", "isEnabled"])
    }

    @MainActor @Test func theCatalogRowsComeFromTheGenerator() throws {
        let toggle = try #require(SettingsCatalog.option("face.presence"))
        #expect(toggle.section == .privacy)
        #expect(toggle.group == "Face presence")
        #expect(toggle.kind == .toggle)
        #expect(toggle.defaultValue == "false")
        #expect(toggle.state == .live)
        let lock = try #require(SettingsCatalog.option("face.lockAfter"))
        #expect(lock.section == .privacy)
        #expect(lock.group == "Face presence")
        #expect(lock.kind == .choice)
        #expect(lock.choices == FacePresenceCardModel.lockAfterChoices)
        #expect(lock.defaultValue == "2 minutes")
        #expect(lock.state == .live)
        let status = try #require(SettingsCatalog.option("face.status"))
        #expect(status.section == .privacy)
        #expect(status.group == "Face presence")
        #expect(status.kind == .status)
        #expect(status.state == .custom)
        // The card, the stored switch and the controller read the same two ids.
        #expect(FacePresenceController.switchID == toggle.id)
        #expect(FacePresenceController.lockAfterID == lock.id)
    }

    @Test func theRenderedFixturesShowEveryStatusWordAndTheFaceRows() {
        let fixtures = FacePresenceCardFixtures.all
        #expect(Set(fixtures.map(\.name)).count == fixtures.count)
        let words = Set(fixtures.map(\.model.status.word))
        for word in ["Off", "Needs camera", "Enrolling", "Watching", "Present", "Away 1:42", "Locked", "Paused", "Unavailable"] {
            #expect(words.contains(word), "no fixture shows \(word)")
        }
        #expect(fixtures.contains { $0.model.faces.count >= 2 && $0.model.faces.contains { !$0.isEnabled } })
        #expect(fixtures.contains { $0.model.enrollEnabled })
        #expect(fixtures.contains { !$0.model.enrollEnabled })
        #expect(fixtures.allSatisfy { $0.name.hasPrefix("face-presence-card") })
    }
}
