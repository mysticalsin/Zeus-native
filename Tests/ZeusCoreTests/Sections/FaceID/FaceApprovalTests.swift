import Foundation
import Testing
@testable import ZeusCore

@Suite("Face approval")
struct FaceApprovalTests {
    @Test func faceApprovalSettingIsOffAndTheKillSwitchStopsTheCamera() {
        let fresh = FaceVerificationMachine()
        #expect(fresh.phase == .disabled)
        #expect(!fresh.approvalEnabled)
        #expect(!fresh.wantsCamera)
        #expect(fresh.grant == nil)
        #expect(FacePresenceLink.defaultEnabled == false)
        #expect(FaceVerificationSectionModel.persistsApprovalSwitch)
        #expect(FaceVerificationSectionModel.persistedKeys.contains(FaceApprovalPreference.key))

        var live = FaceVerificationFixtures.capturing()
        #expect(live.wantsCamera)
        let effects = live.handle(.disable)
        #expect(effects.contains(.stopCamera))
        #expect(live.phase == .disabled)
        #expect(!live.approvalEnabled)
        #expect(!live.wantsCamera)
        _ = live.handle(.identity(matched: true, uptime: 50))
        _ = live.handle(.beginApproval(FaceVerificationFixtures.action("after-kill"), uptime: 51))
        #expect(live.grant == nil)
        #expect(live.phase == .disabled)
        #expect(!live.wantsCamera)
    }

    @Test func genuineAndImpostorVectorsAreOrderedByDistance() {
        let owner: [Float] = [1, 1, 1, 1]
        let genuine: [Float] = [1, 1, 1, 1]
        let impostor: [Float] = [1, -1, 1, -1]
        let near = FaceMatch.distance(genuine, owner)
        let far = FaceMatch.distance(impostor, owner)
        #expect(near < far)
        #expect(near <= FaceVerificationPolicy.acceptDistance)
        #expect(far > FaceVerificationPolicy.acceptDistance)
        #expect(FaceVerificationMatch.accepts(observation: genuine, enrolled: owner))
        #expect(!FaceVerificationMatch.accepts(observation: impostor, enrolled: owner))

        #expect(FaceVerificationMatch.accepts(distance: 0))
        #expect(FaceVerificationMatch.accepts(distance: FaceVerificationPolicy.acceptDistance))
        #expect(!FaceVerificationMatch.accepts(distance: FaceVerificationPolicy.acceptDistance + 0.000_1))
        #expect(!FaceVerificationMatch.accepts(distance: .infinity))
        #expect(!FaceVerificationMatch.accepts(distance: .nan))
        #expect(!FaceVerificationMatch.accepts(distance: -0.01))

        let samples: [Float] = [0, 0.2, 0.44, FaceVerificationPolicy.acceptDistance, 0.46, 1, 2]
        let accepted = samples.filter { FaceVerificationMatch.accepts(distance: $0) }
        let rejected = samples.filter { $0.isFinite && !FaceVerificationMatch.accepts(distance: $0) }
        #expect(!accepted.isEmpty)
        #expect(!rejected.isEmpty)
        #expect(accepted.allSatisfy { candidate in rejected.allSatisfy { candidate < $0 } })
    }

    @Test func photoReplayAndVirtualCameraAreRejected() {
        #expect(!FaceVerificationMatch.acceptFrame(distance: 0, spoof: [.glossGlare], virtualCamera: false))
        #expect(!FaceVerificationMatch.acceptFrame(distance: 0, spoof: [.deviceBezel], virtualCamera: false))
        #expect(!FaceVerificationMatch.acceptFrame(distance: 0, spoof: [.glossGlare, .deviceBezel], virtualCamera: false))
        #expect(!FaceVerificationMatch.acceptFrame(distance: 0, spoof: [], virtualCamera: true))
        #expect(FaceVerificationMatch.acceptFrame(distance: 0, spoof: [], virtualCamera: false))
        #expect(!FaceVerificationMatch.acceptFrame(distance: 2, spoof: [], virtualCamera: false))
        #expect(!FaceVerificationMatch.acceptFrame(distance: 2, spoof: [.glossGlare], virtualCamera: false))

        var machine = FaceVerificationFixtures.capturing()
        _ = machine.handle(.capture(.seen(distance: 0, spoof: [.deviceBezel], virtualCamera: false), uptime: 11))
        #expect(machine.phase != .livenessCheck)
        #expect(machine.phase != .matched)
        #expect(machine.grant == nil)

        var virtual = FaceVerificationFixtures.capturing(nonce: "virtual")
        _ = virtual.handle(.capture(.seen(distance: 0, spoof: [], virtualCamera: true), uptime: 11))
        #expect(virtual.phase != .matched)
        #expect(virtual.grant == nil)
    }

    @Test func lowLightFarNearOccludedNoCameraDeniedAndTimeoutEachHaveASentenceAndATouchIDFallback() {
        let named: [FaceVerificationFailure] = [.lowLight, .tooFar, .tooNear, .occluded, .noCamera, .permissionDenied, .timeout]
        #expect(FaceVerificationFailure.allCases.count == 8)
        #expect(Set(named).isSubset(of: Set(FaceVerificationFailure.allCases)))
        let sentences = FaceVerificationFailure.allCases.map { FaceVerificationCopy.sentence($0) }
        #expect(Set(sentences).count == sentences.count)
        for failure in FaceVerificationFailure.allCases {
            let sentence = FaceVerificationCopy.sentence(failure)
            #expect(!sentence.isEmpty)
            #expect(sentence.contains("password"))
            let offer = FaceVerificationCopy.fallbackOffer(canApproveNow: true)
            #expect(offer.touch)
            #expect(offer.watch)
            #expect(offer.password)
            #expect(offer.canApproveNow)
        }
        let locked = FaceVerificationCopy.fallbackOffer(canApproveNow: false)
        #expect(!locked.canApproveNow)
        #expect(FaceVerificationCopy.locked.contains("locked"))
    }

    @Test func lockoutAfterNFailuresCannotApprove() {
        let limit = 5
        let lockout = 60.0
        #expect(FaceVerificationPolicy.failureLimit == limit)
        #expect(FaceVerificationPolicy.lockoutSeconds == lockout)
        let started = 1_000.0
        var machine = FaceVerificationFixtures.fail(times: limit - 1, at: started)
        #expect(machine.phase == .rejected)
        #expect(machine.failures == limit - 1)
        #expect(machine.grant == nil)
        #expect(machine.fallbackOffer?.canApproveNow == true)

        _ = machine.handle(.beginApproval(FaceVerificationFixtures.action("final"), uptime: started))
        _ = machine.handle(.capture(.noFace, uptime: started))
        #expect(machine.phase == .lockedOut)
        #expect(machine.failures == limit)
        #expect(machine.lockoutStarted == started)
        #expect(machine.grant == nil)
        #expect(machine.fallbackOffer?.canApproveNow == false)
        #expect(!machine.wantsCamera)

        let action = FaceVerificationFixtures.action("during-lock")
        _ = machine.handle(.beginApproval(action, uptime: started + 1))
        _ = machine.handle(.capture(.seen(distance: 0, spoof: [], virtualCamera: false), uptime: started + 1))
        _ = machine.handle(.liveness(FaceLivenessResult(blinked: true, turnedHead: true, virtualCamera: false), uptime: started + 1))
        _ = machine.handle(.identity(matched: true, uptime: started + 1))
        _ = machine.handle(.chooseFallback)
        _ = machine.handle(.fallbackResult(succeeded: true, action: action, uptime: started + 1))
        #expect(machine.phase == .lockedOut)
        #expect(machine.grant == nil)
        #expect(machine.audit.contains { $0.result == .locked })
    }

    @Test func theAuditLineHasNoEmbeddingAndTheKillSwitchStopsTheCamera() throws {
        let embedding: [Float] = [0.123_456_7, 0.234_567_8, 0.345_678_9]
        var machine = FaceVerificationFixtures.matched()
        let effects = machine.handle(.disable)
        #expect(effects.contains(.stopCamera) == false)
        #expect(machine.phase == .disabled)
        #expect(machine.grant == nil)

        let rendered = FaceVerificationPrivacy.crashText(audit: FaceVerificationFixtures.matched().audit, samples: [embedding])
        let analytics = FaceVerificationPrivacy.analyticsText(audit: FaceVerificationFixtures.matched().audit, samples: [embedding])
        for value in embedding {
            #expect(!rendered.contains(String(value)))
            #expect(!analytics.contains(String(value)))
        }
        let encoded = try JSONEncoder().encode(FaceVerificationFixtures.matched().audit)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        #expect(json.allSatisfy { Set($0.keys) == ["time", "result"] })
        let blob = String(decoding: encoded, as: UTF8.self)
        #expect(!blob.contains("embedding"))
        #expect(!blob.contains("image"))
        #expect(!blob.contains("0.1234567"))
    }

    @Test func enrolmentStoresNoImage() throws {
        let key = FaceVault.makeKey()
        let image = Data([0xFF, 0xD8, 0xFF, 0x11, 0x22])
        let thumbnail = Data([0x89, 0x50, 0x4E, 0x47])
        let pictured = FaceEnrollmentDraft(id: "face", name: "Owner", samples: [[1, 0]], image: image, thumbnail: nil)
        #expect(throws: FaceTemplateError.imageRefused) {
            _ = try FaceTemplatePolicy.seal(pictured, key: key, protection: .keychainUserPresence)
        }
        let thumb = FaceEnrollmentDraft(id: "face", name: "Owner", samples: [[1, 0]], image: nil, thumbnail: thumbnail)
        #expect(throws: FaceTemplateError.imageRefused) {
            _ = try FaceTemplatePolicy.seal(thumb, key: key, protection: .keychainUserPresence)
        }
        #expect(throws: FaceTemplateError.unprotectedKey) {
            _ = try FaceTemplatePolicy.seal(
                FaceEnrollmentDraft(id: "face", name: "Owner", samples: [[1, 0]], image: nil, thumbnail: nil),
                key: key,
                protection: .none
            )
        }

        let draft = FaceEnrollmentDraft(id: "face", name: "Owner", samples: [[1, 0], [0.9, 0.1]], image: nil, thumbnail: nil)
        let sealed = try FaceTemplatePolicy.seal(draft, key: key, protection: .keychainUserPresence)
        let opened = try FaceVault.open(sealed, key: key)
        let plain = try JSONEncoder().encode(opened)
        let text = String(decoding: plain, as: UTF8.self)
        #expect(!text.contains("image"))
        #expect(!text.contains("thumbnail"))
        #expect(!text.contains("jpeg"))
        #expect(!sealed.elementsEqual(image))

        let dirty = Data(#"{"samples":[[1,0]],"image":"abc","thumbnail":"def"}"#.utf8)
        #expect(throws: FaceTemplateError.imageRefused) {
            try FaceTemplatePolicy.validateJSON(dirty)
        }
        try FaceTemplatePolicy.validateJSON(Data(#"{"samples":[[1,0]],"revision":1,"threshold":0.4}"#.utf8))

        var cabinet = FaceTemplateCabinet()
        cabinet.store(sealed)
        #expect(cabinet.sealed == sealed)
        cabinet.delete()
        #expect(cabinet.sealed == nil)
        #expect(cabinet.isEmpty)
    }

    @Test func approvalSyncUsesFaceBeforeItClearsBothSides() {
        let action = FaceVerificationFixtures.action("nonce-sync", id: "card-and-terminal")
        var machine = FaceVerificationFixtures.passedLiveness(nonce: action.nonce, id: action.id)
        _ = machine.handle(.identity(matched: false, uptime: 12))
        let refused = ApprovalFaceGate.clear(grant: machine.grant, action: action, consumed: [])
        #expect(refused.sides == .neither)
        #expect(!refused.sides.cardCleared)
        #expect(!refused.sides.terminalCleared)

        var approved = FaceVerificationFixtures.matched(nonce: action.nonce, id: action.id)
        let cleared = ApprovalFaceGate.clear(grant: approved.grant, action: action, consumed: [])
        #expect(cleared.sides.cardCleared)
        #expect(cleared.sides.terminalCleared)
        #expect(cleared.sides.cardCleared == cleared.sides.terminalCleared)

        let replay = ApprovalFaceGate.clear(grant: approved.grant, action: action, consumed: cleared.consumed)
        #expect(replay.sides == .neither)
        let other = FaceVerificationFixtures.action("other-nonce", id: "other-action")
        let mismatched = ApprovalFaceGate.clear(grant: approved.grant, action: other, consumed: [])
        #expect(mismatched.sides == .neither)

        let stale = approved.grant
        _ = approved.handle(.beginApproval(other, uptime: 30))
        #expect(approved.phase == .capturing)
        #expect(approved.grant == nil)
        #expect(approved.openAction == other)
        #expect(ApprovalFaceGate.clear(grant: stale, action: other, consumed: []).sides == .neither)
    }

    @Test func faceUnlockWithNetworkAndLLMStubbedToThrowDoesNotCallEither() {
        var network = FaceSideEffectProbe()
        var model = FaceSideEffectProbe()
        let result = FaceVerificationPipeline.run(network: &network, model: &model)
        #expect(!network.entered)
        #expect(!model.entered)
        #expect(result.finishedLocally)
        #expect(result.enrolled)
        #expect(result.faceApproved)
        #expect(result.fallbackApproved)
        #expect(result.presence == .present)
    }
}
