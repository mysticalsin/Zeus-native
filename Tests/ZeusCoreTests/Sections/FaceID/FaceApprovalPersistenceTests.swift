import Foundation
import Testing
@testable import ZeusCore

@Suite("Face approval persistence")
struct FaceApprovalPersistenceTests {
    @Test func theSwitchSurvivesRecreatingTheSameStoreAndDefaultsOff() {
        var store = FaceApprovalMemory()
        #expect(!store.isOn)
        #expect(FaceApprovalPreference.isOn(nil) == false)
        #expect(FaceApprovalPreference.storedDefault == "false")
        store.setOn(true)
        let restored = FaceApprovalMemory(values: store.values)
        #expect(restored.isOn)
        #expect(restored.values[FaceApprovalPreference.key] == "true")
        var again = restored.recreated()
        #expect(again.isOn)
        again.setOn(false)
        #expect(!again.recreated().isOn)
    }

    @Test func anImportCanNeverTurnTheSwitchOn() {
        let item = FaceApprovalPreference.contribution
        #expect(item == FaceIDSectionSlot.keyContributions.first)
        #expect(item.policy == .importCannotEnable)
        #expect(item.defaultValue == "false")
        #expect(item.kind == .toggle)
        #expect(SettingsKeyLedger.imported(item, current: "false", incoming: "true") == nil)
        #expect(SettingsKeyLedger.imported(item, current: "true", incoming: "false") == "false")
        #expect(SettingsKeyLedger.imported(item, current: "true", incoming: "true") == "true")
        #expect(SettingsKeyLedger.load(item, stored: nil) == "false")

        var off = FaceApprovalMemory()
        off.importFile([FaceApprovalPreference.key: "true", "face.lockAfter": "5 minutes"])
        #expect(!off.isOn)
        #expect(off.values[FaceApprovalPreference.key] != "true")
        #expect(off.values["face.lockAfter"] == "5 minutes")

        var on = FaceApprovalMemory()
        on.setOn(true)
        on.importFile([FaceApprovalPreference.key: "true"])
        #expect(on.isOn)
        on.importFile([FaceApprovalPreference.key: "false"])
        #expect(!on.isOn)
    }

    @Test func anExportNeverCarriesATemplateOrEmbedding() {
        var store = FaceApprovalMemory()
        store.setOn(true)
        let samples: [[Float]] = [[0.123_456, 0.654_321], [0.222_222, 0.333_333]]
        let text = FaceApprovalPreference.exportDocument(settings: store.values, samples: samples)
        #expect(text.contains("\(FaceApprovalPreference.key)=true"))
        let exported = SettingsKeyLedger.exportMap(stored: store.values, contributions: FaceIDSectionSlot.keyContributions)
        #expect(exported[FaceApprovalPreference.key] == "true")
        let blob = text + exported.values.joined(separator: "\n")
        for sample in samples.flatMap({ $0 }) {
            #expect(!blob.contains(String(sample)))
        }
        for word in ["samples", "embedding", "thumbnail", "template", "0.123456"] {
            #expect(!blob.contains(word))
        }
        #expect(FaceIDSectionSlot.keyContributions.allSatisfy { $0.kind == .toggle })
    }

    @Test func theSwitchIsASlotContributionAndNotACatalogRow() throws {
        let item = try #require(FaceIDSectionSlot.keyContributions.first { $0.id == FaceApprovalPreference.key })
        #expect(item.defaultValue == "false")
        #expect(item.policy == .importCannotEnable)
        let root = repositoryRoot()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let generator = try String(contentsOf: root.appendingPathComponent("scripts/gen-settings-catalog.py"), encoding: .utf8)
        #expect(!catalog.contains("\"face.approval\""))
        #expect(!generator.contains("face.approval"))
        let problems = SettingsKeyLedger.problems(
            catalogIDs: SettingsKeyReachability.catalogIDs(in: catalog),
            contributions: GlassSectionManifest.keyContributions
        )
        #expect(problems.isEmpty, "\(problems)")
    }
}

@Suite("Face approval wiring")
struct FaceApprovalWiringTests {
    @Test func theCameraStaysOffUntilTheSwitchIsOn() {
        var session = FaceApprovalSession()
        var camera = FakeApprovalCamera()
        let action = ApprovalAction(id: "save", nonce: "n1")
        let ignored = session.begin(action, camera: &camera, at: 5)
        #expect(ignored == .stopped)
        #expect(!camera.running)
        #expect(camera.accessRequests == 0)
        session.setEnabled(true, enrolled: true, camera: &camera, at: 6)
        #expect(camera.accessRequests == 1)
        #expect(!camera.running)
        let started = session.begin(action, camera: &camera, at: 7)
        #expect(started == .watching)
        #expect(camera.running)
        session.setEnabled(false, enrolled: true, camera: &camera, at: 8)
        #expect(!camera.running)
        #expect(session.machine.phase == .disabled)
    }

    @Test func aFailedLivenessUsesBiometricsThenThePassword() {
        var session = enabledSession()
        var camera = FakeApprovalCamera(access: .authorized)
        let action = ApprovalAction(id: "pay", nonce: "nonce-pay")
        _ = session.begin(action, camera: &camera, at: 10)
        let seen = session.observe(cleanFace(blinked: false, turned: false), camera: &camera, at: 11)
        #expect(seen == .authenticateOwner)
        var auth = ScriptedAuthenticator(biometrics: .unavailable, password: .acceptedPassword)
        let grant = session.authenticate(using: &auth, action: action, camera: &camera, at: 12)
        #expect(auth.policies == [.biometrics, .deviceOwner])
        #expect(grant == FaceApprovalGrant(actionID: action.id, nonce: action.nonce, method: .localAuthentication))
        #expect(!camera.running)
    }

    @Test func biometricsSuccessDoesNotAskForThePassword() {
        var session = enabledSession()
        var camera = FakeApprovalCamera(access: .authorized)
        let action = ApprovalAction(id: "pay", nonce: "nonce-bio")
        _ = session.begin(action, camera: &camera, at: 3)
        _ = session.observe(cleanFace(blinked: false, turned: false), camera: &camera, at: 4)
        var auth = ScriptedAuthenticator(biometrics: .acceptedBiometrics, password: .refused)
        let grant = session.authenticate(using: &auth, action: action, camera: &camera, at: 5)
        #expect(auth.policies == [.biometrics])
        #expect(grant?.method == .localAuthentication)
    }

    @Test func lockoutStillRefusesAFaceAndAcceptsOwnerAuthentication() {
        var session = enabledSession()
        var camera = FakeApprovalCamera(access: .authorized)
        let limit = FaceVerificationPolicy.failureLimit
        for index in 0..<limit {
            let action = ApprovalAction(id: "try", nonce: "lock-\(index)")
            _ = session.begin(action, camera: &camera, at: 100)
            let follow = session.observe(.failure(.timeout), camera: &camera, at: 100)
            if index + 1 == limit {
                #expect(follow == .authenticateOwner)
                #expect(session.machine.phase == .lockedOut)
            }
        }
        let locked = ApprovalAction(id: "try", nonce: "during")
        let face = session.observe(cleanFace(blinked: true, turned: true), camera: &camera, at: 101)
        #expect(face != .approved(FaceApprovalGrant(actionID: locked.id, nonce: locked.nonce, method: .face)))
        #expect(session.machine.grant == nil)
        var auth = ScriptedAuthenticator(biometrics: .unavailable, password: .acceptedPassword)
        let grant = session.authenticate(using: &auth, action: ApprovalAction(id: "try", nonce: "lock-\(limit - 1)"), camera: &camera, at: 102)
        #expect(grant?.method == .localAuthentication)
        #expect(session.machine.phase != .matched)
    }

    @Test func aRestoredOnSwitchCanStartACheckWithoutAskingAgain() {
        var saved = FaceApprovalMemory()
        saved.setOn(true)
        let restored = saved.recreated()
        var session = FaceApprovalSession()
        var camera = FakeApprovalCamera(access: .authorized)
        session.restore(enabled: restored.isOn, enrolled: true, camera: &camera, at: 1)
        #expect(session.machine.approvalEnabled)
        #expect(!camera.running)
        _ = session.begin(ApprovalAction(id: "a", nonce: "restored"), camera: &camera, at: 2)
        #expect(camera.running)
    }
}

private func repositoryRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while url.path != "/" {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift").path) {
            return url
        }
        url.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: #filePath)
}

private func enabledSession() -> FaceApprovalSession {
    var session = FaceApprovalSession()
    var camera = FakeApprovalCamera(access: .authorized)
    session.setEnabled(true, enrolled: true, camera: &camera, at: 1)
    return session
}

private func cleanFace(blinked: Bool, turned: Bool) -> FaceApprovalObservation {
    FaceApprovalObservation(distance: 0, spoof: [], virtualCamera: false, blinked: blinked, turnedHead: turned, failure: nil)
}

private struct FakeApprovalCamera: FaceApprovalCameraDriving {
    var access: FaceCameraAccess = .authorized
    var running = false
    var accessRequests = 0

    mutating func requestAccessIfNeeded() -> FaceCameraAccess {
        accessRequests += 1
        return access
    }

    mutating func setRunning(_ running: Bool) {
        self.running = running
    }
}

private struct ScriptedAuthenticator: FaceApprovalAuthenticating {
    var biometrics: FaceOwnerAuthentication
    var password: FaceOwnerAuthentication
    var policies: [FaceAuthenticationPolicy] = []

    mutating func evaluate(_ policy: FaceAuthenticationPolicy) -> FaceOwnerAuthentication {
        policies.append(policy)
        switch policy {
        case .biometrics: return biometrics
        case .deviceOwner: return password
        }
    }
}
