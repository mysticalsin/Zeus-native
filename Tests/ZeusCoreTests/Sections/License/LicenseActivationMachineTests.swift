import Foundation
import Testing
@testable import ZeusCore

@Suite struct LicenseActivationMachineTests {
    private let secret = "ZEUS1.payloadsecret.sigVALUE"

    @Test func phasesAreTheNamedActivationStates() {
        #expect(Set(LicenseActivationPhase.allCases.map(\.rawValue)) == [
            "unlicensed", "trial", "activating", "active", "releasing", "error",
        ])
    }

    @Test func licenseSectionStillReachesTheExistingLicenseRow() {
        let slot = LicenseSectionSlot.descriptor
        #expect(slot.id == "glass.license")
        #expect(slot.id != "license")
        #expect(slot.id != "general")
        #expect(slot.keys.isEmpty)
        #expect(slot.filled == false)
        let card = LicenseCardPresentation.make(state(.trialEnded))
        let ids = Set(card.controls.map(\.id))
        #expect(ids.contains("glass.license.key"))
        #expect(ids.contains("glass.license.activate"))
        #expect(ids.allSatisfy { $0.hasPrefix("glass.license.") })
        #expect(!ids.contains("license"))
        #expect(!ids.contains("general"))
    }

    @Test func trialDayBoundariesMapOntoTrialOrUnlicensed() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let evaluator = LicenseEvaluator(publicKeys: [], deviceID: "mac")
        let day13 = evaluator.evaluate(.init(key: nil, trialStart: start, now: start.addingTimeInterval(86_400 * 13)))
        let day14 = evaluator.evaluate(.init(key: nil, trialStart: start, now: start.addingTimeInterval(86_400 * 14)))
        #expect(Trial.daysLeft(start: start, now: start.addingTimeInterval(86_400 * 13)) == 1)
        #expect(Trial.daysLeft(start: start, now: start.addingTimeInterval(86_400 * 14)) == 0)
        #expect(day13 == .trial(daysLeft: 1))
        #expect(day14 == .trialEnded)
        #expect(LicenseActivationMachine.initial(facts: facts(day13), reduceMotion: false).phase == .trial)
        #expect(LicenseActivationMachine.initial(facts: facts(day14), reduceMotion: false).phase == .unlicensed)
        #expect(LicenseActivationMachine.restingPhase(for: .trial(daysLeft: 14)) == .trial)
        #expect(LicenseActivationMachine.restingPhase(for: .trial(daysLeft: 1)) == .trial)
        #expect(LicenseActivationMachine.restingPhase(for: .trialEnded) == .unlicensed)
        #expect(LicenseActivationMachine.restingPhase(for: .expired(samplePayload())) == .unlicensed)
        #expect(LicenseActivationMachine.restingPhase(for: .revoked(samplePayload())) == .unlicensed)
        #expect(LicenseActivationMachine.restingPhase(for: .licensed(samplePayload(), daysLeft: nil)) == .active)
        #expect(LicenseActivationMachine.restingPhase(for: .licensed(samplePayload(), daysLeft: 0)) == .active)
    }

    @Test func emptyAndWhitespaceKeysDoNotActivate() {
        for draft in ["", "   ", "\n\t"] {
            let (next, effects) = LicenseActivationMachine.step(state(.trialEnded, draft: draft), .activate)
            #expect(next.phase == .unlicensed)
            #expect(effects.isEmpty)
        }
    }

    @Test func activateMovesFromUnlicensedAndTrialIntoActivating() {
        for status in [LicenseStatus.trialEnded, .trial(daysLeft: 14)] {
            let (next, effects) = LicenseActivationMachine.step(state(status, draft: "  \(secret)  "), .activate)
            #expect(next.phase == .activating)
            #expect(next.revealed == false)
            #expect(next.draft.normalized == secret)
            #expect(effects.count == 1)
            guard case .activateOnThisMac(let handed) = effects.first else {
                Issue.record("expected one activate effect")
                return
            }
            #expect(handed == LicenseKeyDraft(secret))
            expectClean(String(reflecting: effects), key: secret)
            expectClean(next.description, key: secret)
        }
    }

    @Test func aStaleReplyDoesNotMoveASettledPhase() {
        let licensed = state(.licensed(samplePayload(), daysLeft: nil), key: secret)
        let (next, effects) = LicenseActivationMachine.step(licensed, .activationFinished(facts(.trialEnded), message: "stale \(secret)"))
        #expect(next.phase == .active)
        #expect(next.facts.storedKey.normalized == secret)
        #expect(effects.isEmpty)
        expectClean(String(reflecting: next), key: secret)
        let (still, release) = LicenseActivationMachine.step(licensed, .releaseFinished(facts(.trialEnded), message: nil))
        #expect(still.phase == .active)
        #expect(release.isEmpty)
    }

    @Test func aSecondActivateWhileCheckingIsIgnored() {
        let (busy, _) = LicenseActivationMachine.step(state(.trialEnded, draft: secret), .activate)
        let (again, effects) = LicenseActivationMachine.step(busy, .activate)
        #expect(again.phase == .activating)
        #expect(effects.isEmpty)
        let (_, release) = LicenseActivationMachine.step(busy, .confirmRelease)
        #expect(release.isEmpty)
        let (_, copied) = LicenseActivationMachine.step(busy, .copyKey)
        #expect(copied.isEmpty)
    }

    @Test func refreshDoesNotLeaveAnInFlightPhase() {
        let (busy, _) = LicenseActivationMachine.step(state(.trialEnded, draft: secret), .activate)
        let refreshed = facts(.licensed(samplePayload(), daysLeft: nil), key: secret)
        let (next, effects) = LicenseActivationMachine.step(busy, .replaceFacts(refreshed))
        #expect(next.phase == .activating)
        #expect(next.facts == refreshed)
        #expect(effects.isEmpty)
    }

    @Test func successLandsOnActiveAndDropsTheDraft() {
        let (busy, _) = LicenseActivationMachine.step(state(.trial(daysLeft: 3), draft: secret), .activate)
        let stored = facts(.licensed(samplePayload(), daysLeft: nil), key: secret, seat: "Mac 1 of 2")
        let (next, effects) = LicenseActivationMachine.step(busy, .activationFinished(stored, message: nil))
        #expect(next.phase == .active)
        #expect(next.draft.isEmpty)
        #expect(next.failure == nil)
        #expect(next.facts.storedKey.normalized == secret)
        #expect(effects.isEmpty)
        expectClean(next.description, key: secret)
    }

    @Test func aFailureStaysInErrorAndScrubsTheKey() {
        let (busy, _) = LicenseActivationMachine.step(state(.trial(daysLeft: 2), draft: secret), .activate)
        let echoed = "The license server rejected \(secret)"
        let (next, _) = LicenseActivationMachine.step(busy, .activationFinished(facts(.trial(daysLeft: 2)), message: echoed))
        #expect(next.phase == .error)
        #expect(next.failure?.resume == .trial)
        expectClean(next.failure?.message ?? "", key: secret)
        expectClean(String(reflecting: next), key: secret)
        let (restored, effects) = LicenseActivationMachine.step(next, .dismissError)
        #expect(restored.phase == .trial)
        #expect(restored.failure == nil)
        #expect(effects.isEmpty)
    }

    @Test func serverReentryFailsClosedWithoutAnActivateEffect() {
        var card = state(.trialEnded, draft: secret)
        card.facts.serverNeedsReentry = true
        let (next, effects) = LicenseActivationMachine.step(card, .activate)
        #expect(next.phase == .error)
        #expect(next.failure?.message == LicenseActivationMachine.reentryMessage)
        #expect(effects.isEmpty)
        #expect(!next.failure!.message.contains("http"))
    }

    @Test func purchaseStaysOnTheTrialAndOpensNoEndpoint() {
        let (next, effects) = LicenseActivationMachine.step(state(.trial(daysLeft: 9)), .purchase)
        #expect(next.phase == .trial)
        #expect(next.purchaseEmphasis)
        #expect(effects == [.showPurchaseNote])
        #expect(LicenseActivationMachine.endpoint(for: .showPurchaseNote) == nil)
        #expect(LicenseActivationMachine.endpoint(for: .copyKey(LicenseKeyDraft(secret))) == nil)
        #expect(LicenseActivationMachine.endpoint(for: .activateOnThisMac(LicenseKeyDraft(secret))) == .activate)
        #expect(LicenseActivationMachine.endpoint(for: .releaseThisMac) == .deactivate)
        #expect(Set(LicenseActivationEndpoint.allCases.map(\.rawValue)) == [
            "api/v1/activate", "api/v1/deactivate", "api/v1/revocations",
        ])
        let (licensed, none) = LicenseActivationMachine.step(state(.licensed(samplePayload(), daysLeft: nil), key: secret), .purchase)
        #expect(licensed.phase == .active)
        #expect(none.isEmpty)
    }

    @Test func releaseRequiresAnInlineConfirmation() {
        let licensed = state(.licensed(samplePayload(), daysLeft: 20), key: secret)
        let (unarmed, early) = LicenseActivationMachine.step(licensed, .confirmRelease)
        #expect(unarmed.phase == .active)
        #expect(early.isEmpty)
        let (armed, arming) = LicenseActivationMachine.step(licensed, .armRelease)
        #expect(armed.phase == .active)
        #expect(armed.releaseArmed)
        #expect(arming.isEmpty)
        let (cancelled, cancel) = LicenseActivationMachine.step(armed, .cancelRelease)
        #expect(cancelled.releaseArmed == false)
        #expect(cancelled.phase == .active)
        #expect(cancel.isEmpty)
        let (releasing, effects) = LicenseActivationMachine.step(armed, .confirmRelease)
        #expect(releasing.phase == .releasing)
        #expect(releasing.releaseArmed == false)
        #expect(effects == [.releaseThisMac])
    }

    @Test func releaseFromTrialWithoutAKeyDoesNothing() {
        let (next, effects) = LicenseActivationMachine.step(state(.trial(daysLeft: 4)), .armRelease)
        #expect(next.phase == .trial)
        #expect(next.releaseArmed == false)
        #expect(effects.isEmpty)
    }

    @Test func aFinishedReleaseReturnsToTheTrialThatIsLeft() {
        let (releasing, _) = releasingState()
        let (back, effects) = LicenseActivationMachine.step(releasing, .releaseFinished(facts(.trial(daysLeft: 6)), message: nil))
        #expect(back.phase == .trial)
        #expect(back.facts.storedKey.isEmpty)
        #expect(back.revealed == false)
        #expect(effects.isEmpty)
        let (ended, _) = LicenseActivationMachine.step(releasing, .releaseFinished(facts(.trialEnded), message: nil))
        #expect(ended.phase == .unlicensed)
    }

    @Test func aFailedReleaseStaysOnThisMac() {
        let (releasing, _) = releasingState()
        let (next, _) = LicenseActivationMachine.step(
            releasing,
            .releaseFinished(facts(.licensed(samplePayload(), daysLeft: 20), key: secret), message: "Couldn't free this Mac's seat: offline \(secret)")
        )
        #expect(next.phase == .error)
        #expect(next.failure?.resume == .active)
        #expect(next.facts.storedKey.normalized == secret)
        expectClean(next.failure?.message ?? "", key: secret)
    }

    @Test func copyHappensOnlyFromTheCopyAction() {
        let licensed = state(.licensed(samplePayload(), daysLeft: nil), key: secret)
        let (revealed, revealEffects) = LicenseActivationMachine.step(licensed, .reveal)
        #expect(revealed.revealed)
        #expect(revealEffects.isEmpty)
        let (hidden, hideEffects) = LicenseActivationMachine.step(revealed, .conceal)
        #expect(hidden.revealed == false)
        #expect(hideEffects.isEmpty)
        let (copied, effects) = LicenseActivationMachine.step(licensed, .copyKey)
        #expect(copied.phase == .active)
        #expect(copied.revealed == false)
        #expect(copied.copiedAnnouncement == "License key copied")
        expectClean(copied.copiedAnnouncement ?? "", key: secret)
        guard case .copyKey(let handed) = effects.first, effects.count == 1 else {
            Issue.record("expected one copy effect")
            return
        }
        #expect(handed == LicenseKeyDraft(secret))
        expectClean(String(reflecting: effects), key: secret)
        let (empty, none) = LicenseActivationMachine.step(state(.trialEnded), .copyKey)
        #expect(empty.phase == .unlicensed)
        #expect(none.isEmpty)
        #expect(empty.copiedAnnouncement == nil)
    }

    @Test func editingTheDraftCancelsAPendingRelease() {
        let (armed, _) = LicenseActivationMachine.step(state(.licensed(samplePayload(), daysLeft: nil), key: secret), .armRelease)
        let (next, _) = LicenseActivationMachine.step(armed, .editDraft("ZEUS1.other"))
        #expect(next.releaseArmed == false)
        #expect(next.phase == .active)
    }

    @Test func replacingTheKeyIsAnExplicitStep() {
        let licensed = state(.licensed(samplePayload(), daysLeft: nil), key: secret)
        let (ignored, none) = LicenseActivationMachine.step(licensed, .activate)
        #expect(ignored.phase == .active)
        #expect(none.isEmpty)
        let (editing, _) = LicenseActivationMachine.step(licensed, .beginReplacement)
        #expect(editing.enteringReplacement)
        #expect(editing.phase == .active)
        let (typed, _) = LicenseActivationMachine.step(editing, .editDraft(secret))
        let (busy, effects) = LicenseActivationMachine.step(typed, .activate)
        #expect(busy.phase == .activating)
        #expect(effects.count == 1)
        let (cancelled, _) = LicenseActivationMachine.step(editing, .cancelReplacement)
        #expect(cancelled.enteringReplacement == false)
        #expect(cancelled.draft.isEmpty)
    }

    @Test func descriptionsAndMirrorsNeverExposeTheKey() {
        let draft = LicenseKeyDraft("  \(secret)\n")
        expectClean(draft.description, key: secret)
        expectClean(String(reflecting: draft), key: secret)
        expectClean(String(describing: draft), key: secret)
        let mirror = Mirror(reflecting: draft)
        for child in mirror.children {
            expectClean(String(reflecting: child.value), key: secret)
        }
        let card = state(.licensed(samplePayload(), daysLeft: 4), key: secret, draft: secret)
        expectClean(String(reflecting: card), key: secret)
        expectClean(String(reflecting: card.facts), key: secret)
        let failed = LicenseActivationMachine.step(card, .activationFinished(card.facts, message: "bad \(secret)")).0
        expectClean(String(reflecting: failed), key: secret)
    }

    @Test func maskBoundaryHidesUpToTheVisibleEdges() {
        let nine = "ZEUS1.abc"
        let ten = "ZEUS1.abcd"
        #expect(LicenseKeyPrivacy.mask("") == "")
        #expect(LicenseKeyPrivacy.mask("   ") == "")
        #expect(LicenseKeyPrivacy.mask(nine) == String(repeating: "•", count: nine.count))
        let masked = LicenseKeyPrivacy.mask(ten)
        #expect(masked.hasPrefix("ZEUS1"))
        #expect(masked.hasSuffix("abcd"))
        #expect(masked.contains("••••"))
        expectClean(masked, key: ten)
        let spaced = "ZEUS1. abcdEFGH"
        let compact = spaced.filter { !$0.isWhitespace }
        expectClean(LicenseKeyPrivacy.scrub("echo \(compact)", secrets: [spaced]), key: compact)
        let fragment = "ZEUS1.a"
        let scrubbed = LicenseKeyPrivacy.scrub("\(fragment) \(ten)", secrets: [fragment, ten])
        #expect(scrubbed.contains(fragment))
        expectClean(scrubbed, key: ten)
    }

    @Test func presentationShowsTrialPurchaseAndAMaskedKey() {
        let card = LicenseCardPresentation.make(state(.trial(daysLeft: 11)))
        #expect(card.phase == .trial)
        #expect(card.loading == false)
        #expect(card.empty == false)
        #expect(card.preview.badge == "Trial")
        #expect(card.preview.title == "Trial · 11 days left")
        #expect(card.preview.detail.contains("11 of \(Trial.days) days left"))
        #expect(card.preview.detail.contains("one-time purchase"))
        #expect(card.preview.progress == 11 / Double(Trial.days))
        #expect(card.rowHeight == 52)
        #expect(card.panelPadding == 32)
        #expect(card.cardSpacing == 28)
        #expect(card.motion.duration == MotionTokens.crossfadeDuration)
        #expect(card.motion.pressScale == MotionTokens.pressScale)
        expectControls(card)
        #expect(card.controls.contains { $0.id == "glass.license.purchase" && $0.event == .purchase && $0.helper == LicenseActivationMachine.purchaseNote })
        #expect(card.controls.contains { $0.id == "glass.license.activate" && $0.enabled == false })
    }

    @Test func lastTrialDayAndEndedTrialStayDistinct() {
        let last = LicenseCardPresentation.make(state(.trial(daysLeft: 1)))
        #expect(last.preview.title == "Trial · last day")
        #expect(last.preview.badge == "Trial")
        let ended = LicenseCardPresentation.make(state(.trialEnded))
        #expect(ended.phase == .unlicensed)
        #expect(ended.empty)
        #expect(ended.preview.badge == "Ended")
        #expect(ended.preview.title == "Your free trial has ended.")
        #expect(ended.preview.progress == 0)
        expectControls(ended)
    }

    @Test func reduceMotionRemovesDurationAndPressScale() {
        let card = LicenseCardPresentation.make(state(.trial(daysLeft: 2), reduceMotion: true))
        #expect(card.motion.duration == 0)
        #expect(card.motion.pressScale == 1)
    }

    @Test func activeCardMasksTheKeyUntilRevealAndOffersCopyAndRelease() {
        let hidden = LicenseCardPresentation.make(state(.licensed(samplePayload(name: "Ada"), daysLeft: nil), key: secret))
        #expect(hidden.phase == .active)
        #expect(hidden.preview.badge == "Active")
        #expect(hidden.preview.title == "Zeus is yours.")
        #expect(hidden.preview.detail.contains("Ada"))
        #expect(hidden.loading == false)
        let keyRow = hidden.controls.first { $0.id == "glass.license.key" }
        #expect(keyRow?.accessibilityValue == LicenseKeyPrivacy.mask(secret))
        expectClean(keyRow?.accessibilityValue ?? "", key: secret)
        expectClean(keyRow?.accessibilityLabel ?? "", key: secret)
        #expect(hidden.controls.contains { $0.id == "glass.license.copy" && $0.event == .copyKey })
        #expect(hidden.controls.contains { $0.id == "glass.license.reveal" && $0.event == .reveal })
        #expect(hidden.controls.contains { $0.id == "glass.license.release" && $0.event == .armRelease })
        #expect(!hidden.controls.contains { $0.event == .activate })
        expectControls(hidden)
        let shown = LicenseCardPresentation.make(LicenseActivationMachine.step(state(.licensed(samplePayload(), daysLeft: nil), key: secret), .reveal).0)
        #expect(shown.controls.first { $0.id == "glass.license.key" }?.revealsKey == true)
        let armed = LicenseCardPresentation.make(LicenseActivationMachine.step(state(.licensed(samplePayload(), daysLeft: nil), key: secret), .armRelease).0)
        #expect(armed.controls.contains { $0.id == "glass.license.release" && $0.event == .confirmRelease })
        #expect(armed.controls.contains { $0.id == "glass.license.releaseCancel" && $0.event == .cancelRelease })
        #expect(armed.controls.first { $0.id == "glass.license.release" }?.helper.localizedCaseInsensitiveContains("press again") == true)
    }

    @Test func checkingAndReleasingAreLoadingStates() {
        let checking = LicenseCardPresentation.make(LicenseActivationMachine.step(state(.trialEnded, draft: secret), .activate).0)
        #expect(checking.loading)
        #expect(checking.empty == false)
        #expect(checking.preview.badge == "Checking")
        #expect(checking.controls.first { $0.id == "glass.license.activate" }?.enabled == false)
        #expect(checking.errorMessage == nil)
        let releasing = LicenseCardPresentation.make(releasingState().0)
        #expect(releasing.loading)
        #expect(releasing.preview.badge == "Releasing")
        #expect(releasing.controls.allSatisfy { $0.enabled == false || $0.event == nil })
        expectControls(checking)
        expectControls(releasing)
    }

    @Test func errorsShowAScrubbedMessageAndStayActionable() {
        let failed = LicenseActivationMachine.step(
            LicenseActivationMachine.step(state(.trialEnded, draft: secret), .activate).0,
            .activationFinished(facts(.trialEnded), message: "nope \(secret)")
        ).0
        let card = LicenseCardPresentation.make(failed)
        #expect(card.phase == .error)
        #expect(card.preview.badge == "Error")
        expectClean(card.errorMessage ?? "", key: secret)
        #expect(card.controls.contains { $0.id == "glass.license.error" })
        #expect(card.controls.contains { $0.id == "glass.license.activate" })
        expectControls(card)
        let launch = LicenseActivationMachine.initial(
            facts: facts(.licensed(samplePayload(), daysLeft: nil), key: secret, deactivation: "Couldn't remove the local license credentials."),
            reduceMotion: false
        )
        #expect(launch.phase == .error)
        #expect(launch.failure?.resume == .active)
    }

    @Test func aNoticeOnTheKeyRowIsScrubbedAndDoesNotForceTheErrorPhase() {
        var card = state(.trial(daysLeft: 5))
        card.facts.notice = "Earlier attempt mentioned \(secret)"
        let presentation = LicenseCardPresentation.make(card)
        #expect(presentation.phase == .trial)
        let helper = presentation.controls.first { $0.id == "glass.license.key" }?.helper ?? ""
        expectClean(helper, key: secret)
        #expect(helper.isEmpty == false)
    }

    @Test func randomWalkKeepsTheGuardsAndNeverPublishesTheKey() {
        var rng = SplitMix(state: 0x5EED)
        let statuses: [LicenseStatus] = [
            .trial(daysLeft: 14), .trial(daysLeft: 1), .trialEnded,
            .licensed(samplePayload(), daysLeft: nil), .licensed(samplePayload(), daysLeft: 0),
            .expired(samplePayload()), .revoked(samplePayload()),
        ]
        for sample in 0..<48 {
            var card = state(statuses[rng.int(statuses.count)], key: sample.isMultiple(of: 2) ? secret : "", draft: sample.isMultiple(of: 3) ? secret : "")
            for _ in 0..<24 {
                let event = randomEvent(&rng, key: secret)
                let before = card
                let (next, effects) = LicenseActivationMachine.step(card, event)
                expectClean(String(reflecting: next), key: secret)
                expectClean(String(reflecting: effects), key: secret)
                #expect(LicenseActivationPhase.allCases.contains(next.phase))
                let copyAllowed = event == .copyKey && !before.facts.storedKey.isEmpty && before.phase != .activating && before.phase != .releasing
                #expect(effects.contains(where: { if case .copyKey = $0 { true } else { false } }) == copyAllowed)
                let releaseAllowed = event == .confirmRelease && before.releaseArmed && !before.facts.storedKey.isEmpty && before.phase != .activating && before.phase != .releasing
                #expect(effects.contains(.releaseThisMac) == releaseAllowed)
                if copyAllowed {
                    #expect(next.copiedAnnouncement == "License key copied")
                }
                expectClean(next.copiedAnnouncement ?? "", key: secret)
                let presentation = LicenseCardPresentation.make(next)
                expectClean(String(reflecting: presentation), key: secret)
                expectControls(presentation)
                card = next
            }
        }
    }

    @Test func machineSourcesDoNotLogTheKeyOrAddAnEndpoint() throws {
        let root = try repoRoot()
        let directory = root.appendingPathComponent("Sources/ZeusCore/Settings/Sections/License")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let banned = ["URLSession", "print(", "debugPrint", "NSLog", "os.Logger", "analytics", "http://", "https://", "dump("]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned {
                #expect(!text.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
        let client = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/License/LicenseServerClient.swift"), encoding: .utf8)
        for path in LicenseActivationEndpoint.allCases.map(\.rawValue) {
            #expect(client.contains("\"\(path)\""))
        }
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let marker = "Sources/ZeusCore/License/LicenseServerClient.swift"
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(marker).path) { return url }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func samplePayload(name: String? = nil) -> LicensePayload {
        LicensePayload(id: "L-1", email: "ada@example.com", plan: "lifetime", issued: 1_700_000_000, name: name, seats: 2)
    }

    private func facts(
        _ status: LicenseStatus,
        key: String = "",
        pending: Bool = false,
        reentry: Bool = false,
        server: Bool = false,
        seat: String? = nil,
        deactivation: String? = nil,
        notice: String? = nil
    ) -> LicenseCardFacts {
        LicenseCardFacts(
            status: status,
            storedKey: LicenseKeyDraft(key),
            activationPending: pending,
            serverNeedsReentry: reentry,
            serverConfigured: server,
            seatLabel: seat,
            deactivationError: deactivation,
            notice: notice
        )
    }

    private func state(_ status: LicenseStatus, key: String = "", draft: String = "", reduceMotion: Bool = false) -> LicenseActivationState {
        var card = LicenseActivationMachine.initial(facts: facts(status, key: key), reduceMotion: reduceMotion)
        if !draft.isEmpty {
            card = LicenseActivationMachine.step(card, .editDraft(draft)).0
        }
        return card
    }

    private func releasingState() -> (LicenseActivationState, [LicenseActivationEffect]) {
        let armed = LicenseActivationMachine.step(state(.licensed(samplePayload(), daysLeft: 20), key: secret), .armRelease).0
        return LicenseActivationMachine.step(armed, .confirmRelease)
    }

    private func expectClean(_ text: String, key: String) {
        let clean = !LicenseKeyPrivacy.exposes(text, key: key)
        #expect(clean)
    }

    private func expectControls(_ card: LicenseCardPresentation) {
        #expect(card.rowHeight == LicenseCardLayout.rowHeight)
        #expect(card.panelPadding == LicenseCardLayout.panelPadding)
        #expect(card.cardSpacing == LicenseCardLayout.cardSpacing)
        #expect(card.preview.accessibilityLabel.isEmpty == false)
        expectClean(card.preview.accessibilityLabel, key: secret)
        for control in card.controls {
            #expect(control.id.hasPrefix("glass.license."))
            #expect(control.helper.isEmpty == false)
            #expect(control.accessibilityLabel.isEmpty == false)
            #expect(control.keyboardReachable)
            if control.revealsKey == false {
                expectClean(control.accessibilityValue, key: secret)
                expectClean(control.accessibilityLabel, key: secret)
                expectClean(control.helper, key: secret)
            }
        }
    }

    private func randomEvent(_ rng: inout SplitMix, key: String) -> LicenseActivationEvent {
        switch rng.int(15) {
        case 0: .editDraft(rng.int(4) == 0 ? "  \(key)  " : rng.token(rng.int(12)))
        case 1: .activate
        case 2: .armRelease
        case 3: .confirmRelease
        case 4: .cancelRelease
        case 5: .copyKey
        case 6: .reveal
        case 7: .conceal
        case 8: .purchase
        case 9: .dismissError
        case 10: .beginReplacement
        case 11: .cancelReplacement
        case 12: .setReduceMotion(rng.int(2) == 0)
        case 13: .replaceFacts(facts([LicenseStatus.trial(daysLeft: 3), .trialEnded, .licensed(samplePayload(), daysLeft: nil)][rng.int(3)], key: rng.int(2) == 0 ? key : ""))
        default: .activationFinished(facts(.trialEnded), message: rng.int(2) == 0 ? "rejected \(key)" : nil)
        }
    }
}

/// A small deterministic generator so the property test is the same on every run.
private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
    mutating func token(_ length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet[int(alphabet.count)] })
    }
}
