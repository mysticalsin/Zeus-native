import SwiftUI
import ZeusCore

/// What the Face presence card shows, as plain values: one status, one row per enrolled face, whether Enroll can be
/// tapped and which lock choice is picked. Built from the machine and the vault records, so the view has no rules.
/// Faces carry a name and a switch only: no sample or embedding reaches a view.
struct FacePresenceCardModel: Equatable {
    struct FaceRow: Equatable, Identifiable {
        let id: String
        let name: String
        let isEnabled: Bool
    }

    let status: FacePresenceStatus
    let faces: [FaceRow]
    /// Enroll is enabled only while the switch is on and the state is watching, present or away.
    let enrollEnabled: Bool
    let lockAfterLabel: String
    /// The lock time only matters while Face presence is on; while it is Off the row is dimmed and inert.
    let lockAfterEnabled: Bool
    /// Fingerprints changed, so the saved face print can no longer be read.
    let needsReenrol: Bool

    static let lockAfterChoices = FaceLockAfter.choices.map(\.label)
    static let enrollNote = FaceTemplateCopy.enroll
    static let reenrolNote = FaceTemplateCopy.reenrol

    /// What VoiceOver reads for the status row, "Face presence status: Away, 1 minute 42 seconds left".
    var statusAccessibilityLabel: String { status.accessibilityText }

    static func make(machine: FacePresenceMachine, faces: [FaceRecord], lockAfterLabel: String, uptime: Double,
                     needsReenrol: Bool = false) -> FacePresenceCardModel {
        FacePresenceCardModel(
            status: machine.status(at: uptime),
            faces: faces.map { FaceRow(id: $0.id, name: $0.name, isEnabled: $0.isEnabled) },
            enrollEnabled: machine.canEnroll,
            // A stored label that is not one of the five reads as the default, as the lock rule does.
            lockAfterLabel: lockAfterChoices.contains(lockAfterLabel) ? lockAfterLabel : FaceLockAfter.defaultLabel,
            lockAfterEnabled: machine.state != .off,
            needsReenrol: needsReenrol)
    }
}

/// The card: a switch, the status, one row per face, Enroll and the lock time. Enroll says that saving asks for
/// Touch ID or the device passcode, and that the face print is not kept after a match. A fingerprint change
/// says to enroll again. No preview of the camera. It holds no rules; every tap goes to the closure it was given.
struct GSFacePresenceCard: View {
    let model: FacePresenceCardModel
    @Binding var isOn: Bool
    @Binding var lockAfter: String
    var setFace: (String, Bool) -> Void = { _, _ in }
    var deleteFace: (String) -> Void = { _ in }
    var enroll: () -> Void = {}

    var body: some View {
        GSCard("Face presence") {
            GSToggleRow(symbol: "person.crop.circle", title: "Face presence", isOn: $isOn)
            GSDivider()
            GSRow(symbol: model.status.symbol, title: "Status") {
                // The word changes in place, with tabular numerals so the countdown does not shift. Nothing animates.
                Text(model.status.word)
                    .font(GS.rowTitle.monospacedDigit())
                    .foregroundStyle(GS.text)
                    .accessibilityLabel(model.statusAccessibilityLabel)
            }
            if let hint = model.status.hint {
                Text(hint)
                    .font(OB.font(12.5))
                    .foregroundStyle(GS.text.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, GS.rowIconColumn).padding(.trailing, 16).padding(.vertical, 8)
            }
            ForEach(model.faces) { face in
                GSDivider()
                GSRow(symbol: "person.fill", title: face.name) {
                    HStack(spacing: 14) {
                        Toggle(face.name, isOn: Binding(get: { face.isEnabled }, set: { setFace(face.id, $0) }))
                            .toggleStyle(GSToggleStyle()).labelsHidden()
                        Button { deleteFace(face.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(GSButtonStyle())
                            .accessibilityLabel("Delete \(face.name)")
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "plus.circle", title: "Enroll") {
                Button("Enroll", action: enroll)
                    .buttonStyle(GSButtonStyle())
                    .disabled(!model.enrollEnabled)
            }
            Text(FacePresenceCardModel.enrollNote)
                .font(OB.font(12.5))
                .foregroundStyle(GS.text.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, GS.rowIconColumn).padding(.trailing, 16).padding(.vertical, 8)
                .accessibilityLabel(FacePresenceCardModel.enrollNote)
            if model.needsReenrol {
                Text(FacePresenceCardModel.reenrolNote)
                    .font(OB.font(12.5))
                    .foregroundStyle(GS.text.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, GS.rowIconColumn).padding(.trailing, 16).padding(.bottom, 8)
                    .accessibilityLabel(FacePresenceCardModel.reenrolNote)
            }
            GSDivider()
            GSRow(symbol: "timer", title: "Lock after absent for") {
                GSPopup(selection: $lockAfter, options: FacePresenceCardModel.lockAfterChoices, label: "Lock after absent for")
                    .disabled(!model.lockAfterEnabled)
            }
            .opacity(model.lockAfterEnabled ? 1 : 0.5)
        }
    }
}

/// The card on the Privacy page, tied to the controller and the two stored settings. The status is redrawn every
/// second only while the countdown runs; in every other state it is drawn when the state changes.
struct GSFacePresenceCardHost: View {
    private var controller: FacePresenceController { FacePresenceController.shared }
    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        if case .away = controller.machine.state {
            TimelineView(.periodic(from: .now, by: 1)) { _ in card }
        } else {
            card
        }
    }

    private var card: some View {
        GSFacePresenceCard(
            model: FacePresenceCardModel.make(machine: controller.machine, faces: controller.faces,
                                              lockAfterLabel: store.string(FacePresenceController.lockAfterID),
                                              uptime: ProcessInfo.processInfo.systemUptime,
                                              needsReenrol: controller.needsReenrol),
            isOn: store.boolBinding(FacePresenceController.switchID),
            lockAfter: store.stringBinding(FacePresenceController.lockAfterID),
            setFace: { controller.setFace($0, enabled: $1) },
            deleteFace: { controller.deleteFace($0) },
            enroll: { controller.enroll() })
    }
}

/// States drawn by `Zeus --snapshots` for review: every status word, with and without faces. Fixed values, so the
/// render never touches the controller, the camera, the vault or the Keychain.
enum FacePresenceCardFixtures {
    struct Fixture {
        let name: String
        let model: FacePresenceCardModel
        let isOn: Bool
    }

    private static func machine(_ events: [FacePresenceMachine.Event]) -> FacePresenceMachine {
        var machine = FacePresenceMachine()
        for event in events { _ = machine.handle(event) }
        return machine
    }

    private static func on(camera: FacePresenceMachine.CameraAccess = .authorized, faces: Int = 1) -> FacePresenceMachine.Event {
        .switchOn(camera: camera, enabledFaces: faces, canLock: true, vaultReadable: true, uptime: 100)
    }

    private static func record(_ number: Int, enabled: Bool = true) -> FaceRecord {
        FaceRecord(id: "fixture-\(number)", name: "Face \(number)", isEnabled: enabled, revision: 1, samples: [], threshold: 0.3)
    }

    static let all: [Fixture] = {
        let one = [record(1)]
        let two = [record(1), record(2, enabled: false)]
        func fixture(_ name: String, _ events: [FacePresenceMachine.Event], faces: [FaceRecord], label: String = "2 minutes",
                     at uptime: Double = 100, isOn: Bool = true) -> Fixture {
            Fixture(name: "face-presence-card-\(name)",
                    model: .make(machine: machine(events), faces: faces, lockAfterLabel: label, uptime: uptime), isOn: isOn)
        }
        return [
            fixture("off", [], faces: [], isOn: false),
            fixture("needs-camera", [on(camera: .notDetermined)], faces: one),
            fixture("enrolling", [on(faces: 0)], faces: []),
            fixture("watching", [on()], faces: two, label: "5 minutes"),
            fixture("present", [on(), .observed(.owner, uptime: 101)], faces: two),
            fixture("away", [on(), .observed(.notOwner, uptime: 101)], faces: two, at: 118),
            fixture("locked", [on(), .observed(.notOwner, uptime: 101), .tick(uptime: 220)], faces: one),
            fixture("paused", [.launch(storedOn: true)], faces: one),
            fixture("unavailable", [.switchOn(camera: .authorized, enabledFaces: 1, canLock: false, vaultReadable: true, uptime: 100)],
                    faces: one, label: "30 seconds"),
        ]
    }()
}
