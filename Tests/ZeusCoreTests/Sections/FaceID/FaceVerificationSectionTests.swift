import Foundation
import Testing
@testable import ZeusCore

@Suite("Face verification section")
struct FaceVerificationSectionTests {
    @Test func theCardSitsOnThePrivacyPageAndKeepsThePresenceKey() {
        #expect(FaceVerificationPlacement.standard == .privacyCard(order: 1))
        #expect(FaceIDSectionSlot.descriptor.placement == .cardOn(.privacy, 1))
        let slot = FaceIDSectionSlot.descriptor
        #expect(slot.id == "glass.faceID")
        #expect(slot.filled)
        #expect(slot.keys.isEmpty)
        #expect(FaceVerificationSectionModel.persistedKeys == ["face.approval", "face.presence", "face.lockAfter", "face.status"])
        #expect(FaceVerificationSectionModel.persistedKeys.contains(FaceApprovalPreference.key))
        #expect(FaceVerificationSectionModel.persistsApprovalSwitch)
    }

    @Test func onboardingSaysWhatThisIsAndIsNot() {
        let text = FaceVerificationCopy.onboarding
        #expect(FaceVerificationCopy.title == "Face verification")
        #expect(text.contains("not Face ID"))
        #expect(text.contains("login screen"))
        #expect(text.lowercased().contains("camera"))
        #expect(!text.lowercased().contains("spoof-proof"))
        #expect(!text.lowercased().contains("cannot be fooled"))
    }

    @Test func everyControlHasAHelperAndThePreviewShowsNoFrame() {
        let ready = FaceVerificationSectionModel.make(
            machine: FaceVerificationFixtures.idle(),
            presenceEnabled: false,
            reduceMotion: false,
            vaultReadable: true
        )
        #expect(ready.title == "Face verification")
        #expect(ready.placement == .privacyCard(order: 1))
        #expect(ready.layout == FaceVerificationLayout.standard)
        #expect(ready.layout.rowHeight == 52)
        #expect(ready.layout.panelPadding == 32)
        #expect(ready.layout.cardSpacing == 28)
        #expect(ready.screen == .ready)
        #expect(!ready.preview.showsCameraImage)
        #expect(!ready.preview.accessibilityLabel.isEmpty)
        #expect(ready.animationDuration > 0)
        #expect(!ready.controls.isEmpty)
        for control in ready.controls {
            #expect(!control.helper.isEmpty, "\(control.id)")
            #expect(!control.accessibilityLabel.isEmpty, "\(control.id)")
            #expect(control.keyboardReachable)
        }
        #expect(ready.controls.contains { $0.id == "face.presence" })

        let reduced = FaceVerificationSectionModel.make(
            machine: FaceVerificationMachine(),
            presenceEnabled: false,
            reduceMotion: true,
            vaultReadable: true
        )
        #expect(reduced.animationDuration == 0)
        #expect(reduced.screen == .ready)

        let empty = FaceVerificationSectionModel.make(
            machine: FaceVerificationFixtures.notEnrolled(),
            presenceEnabled: false,
            reduceMotion: true,
            vaultReadable: true
        )
        #expect(empty.screen == .empty)
        #expect(!empty.preview.showsCameraImage)

        let loading = FaceVerificationSectionModel.make(
            machine: FaceVerificationMachine(),
            presenceEnabled: false,
            reduceMotion: true,
            vaultReadable: nil
        )
        #expect(loading.screen == .loading)

        let broken = FaceVerificationSectionModel.make(
            machine: FaceVerificationMachine(),
            presenceEnabled: false,
            reduceMotion: true,
            vaultReadable: false
        )
        if case .error(let message) = broken.screen {
            #expect(!message.isEmpty)
            #expect(!message.contains("0.1234567"))
        } else {
            Issue.record("A vault that cannot be read is an error")
        }
    }
}
