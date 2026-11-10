import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly source selection")
struct RecordlySourceSelectionTests {
    private let displayA = RecordlySourceSelection.CatalogSnapshot.Display(
        id: 17,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )

    @Test func grantedExactDisplayResolvesToThatDisplay() {
        let outcome = resolve(.display(id: 17), displays: [displayA])
        guard case .ready(let source) = outcome else {
            Issue.record("Expected the exact selected display to be ready, got \(outcome).")
            return
        }
        #expect(source.kind == .display)
        #expect(source.displayID == 17)
        #expect(source.cropRect == nil)
        let adapted = RecordlySourceSelection.CaptureAdapter(source)
        #expect(adapted.source == .display(id: 17))
        #expect(adapted.hostDisplayID == 17)
    }

    @Test func missingDisplayIsLostAndNeverReplacedByFirstCatalogDisplay() {
        let outcome = resolve(
            .display(id: 29),
            displays: [displayA, .init(id: 31, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))]
        )
        guard case .lostSource = outcome else {
            Issue.record("Expected the missing exact display to be lost, got \(outcome).")
            return
        }
    }

    @Test func zeroDisplayPlaceholderIsInvalid() {
        guard case .invalidIntent = resolve(.display(id: 0), displays: [displayA]) else {
            Issue.record("Display id 0 must not resolve as a placeholder.")
            return
        }
    }

    @Test func permissionUnknownOrDeniedNeverResolvesReady() {
        for permission in [RecordlySourceSelection.PermissionState.unknown, .denied] {
            let outcome = RecordlySourceSelection.resolve(
                intent: .display(id: 17),
                in: .init(displays: [displayA]),
                permission: permission
            )
            guard case .denied(let reason) = outcome else {
                Issue.record("Permission \(permission) must fail closed, got \(outcome).")
                continue
            }
            #expect(!reason.isEmpty)
        }
    }

    @Test func unprovenancedRegionIntentFailsClosedWithActionableReason() {
        let intent = RecordlySourceSelection.SelectionIntent.region(displayID: 17, x: 12.5, y: 20, width: 400, height: 300)
        let outcome = resolve(intent, displays: [displayA])
        guard case .invalidIntent(let reason) = outcome else {
            Issue.record("Unprovenanced region coordinates must fail closed, got \(outcome).")
            return
        }
        #expect(reason.contains("coordinate-space"))
    }

    @Test func regionIntentRemainsUnavailableAfterHostCatalogChanges() {
        let intent = RecordlySourceSelection.SelectionIntent.region(displayID: 17, x: 12.5, y: 20, width: 400, height: 300)
        let replacement = RecordlySourceSelection.CatalogSnapshot.Display(
            id: 29,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        let swapped = resolve(intent, displays: [replacement])
        guard case .invalidIntent = swapped else {
            Issue.record("Unprovenanced region intent must fail closed regardless of host catalog, got \(swapped).")
            return
        }
    }

    @Test func invalidRegionGeometryIsRejected() {
        let intents: [RecordlySourceSelection.SelectionIntent] = [
            .region(displayID: 17, x: 0, y: 0, width: 0, height: 10),
            .region(displayID: 17, x: 0, y: 0, width: 10, height: -1),
            .region(displayID: 17, x: .nan, y: 0, width: 10, height: 10),
            .region(displayID: 17, x: 0, y: .infinity, width: 10, height: 10)
        ]
        for intent in intents {
            guard case .invalidIntent = resolve(intent, displays: [displayA]) else {
                Issue.record("Invalid region geometry must not resolve, got \(resolve(intent, displays: [displayA])).")
                continue
            }
        }
    }

    @Test func regionIntentFailsClosedWithoutCoordinateProvenanceOutsideCatalogBounds() {
        let outcome = resolve(.region(displayID: 17, x: 1900, y: 900, width: 100, height: 100), displays: [displayA])
        guard case .invalidIntent = outcome else {
            Issue.record("Unprovenanced region must fail closed, got \(outcome).")
            return
        }
    }

    @Test func regionIntentIsRejectedForMalformedAndDuplicateCatalogShapes() {
        let intent = RecordlySourceSelection.SelectionIntent.region(displayID: 17, x: 10, y: 10, width: 20, height: 20)
        let malformedFrames: [CGRect] = [
            CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: CGFloat.nan, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 0)
        ]
        for frame in malformedFrames {
            let outcome = resolve(intent, displays: [displayA, .init(id: 29, frame: frame)])
            guard case .invalidIntent = outcome else {
                Issue.record("Region must remain unavailable regardless of display geometry, got \(outcome).")
                continue
            }
        }

        let duplicate = resolve(intent, displays: [displayA, displayA])
        guard case .invalidIntent = duplicate else {
            Issue.record("Region must remain unavailable with duplicate display identities, got \(duplicate).")
            return
        }
    }

    @Test func exactWindowIdentityResolvesAndMissingOrReusedIdentityDoesNot() {
        let binding = RecordlySourceSelection.CatalogSnapshot.Window(
            number: 9,
            identityToken: "window-token-A",
            isPresent: true
        )
        let exact = resolve(.window(number: 9, identityToken: "window-token-A"), windows: [binding])
        guard case .ready(let source) = exact else {
            Issue.record("Expected exact bound window to resolve, got \(exact).")
            return
        }
        #expect(source.windowNumber == 9)
        #expect(source.windowIdentityToken == "window-token-A")

        let reused = resolve(.window(number: 9, identityToken: "window-token-old"), windows: [binding])
        guard case .lostSource = reused else {
            Issue.record("A reused window number must not select a different window, got \(reused).")
            return
        }

        let absent = resolve(
            .window(number: 9, identityToken: "window-token-A"),
            windows: [.init(number: 9, identityToken: "window-token-A", isPresent: false)]
        )
        guard case .lostSource = absent else {
            Issue.record("A bound but absent window must be lost, got \(absent).")
            return
        }
    }

    @Test func unboundOrNegativeWindowIntentIsInvalid() {
        guard case .invalidIntent = resolve(.window(number: 8, identityToken: "token")) else {
            Issue.record("An unbound window number must be invalid.")
            return
        }
        guard case .invalidIntent = resolve(.window(number: 0, identityToken: "token"), windows: [
            .init(number: 0, identityToken: "token", isPresent: true)
        ]) else {
            Issue.record("Window number 0 must not be treated as a selected source.")
            return
        }
        guard case .invalidIntent = resolve(.window(number: -1, identityToken: "token"), windows: [
            .init(number: -1, identityToken: "token", isPresent: true)
        ]) else {
            Issue.record("Negative window numbers must be invalid.")
            return
        }
    }

    @Test func regionIntentRemainsUnavailableEvenWithOneHostDisplay() {
        let host = RecordlySourceSelection.CatalogSnapshot.Display(id: 17, frame: CGRect(x: -1000, y: 0, width: 1000, height: 800))
        guard case .invalidIntent = RecordlySourceSelection.resolve(intent: .region(displayID: 17, x: 10, y: 10, width: 20, height: 20), in: .init(displays: [host]), permission: .granted) else {
            Issue.record("A host display is not enough to establish the region coordinate contract.")
            return
        }
    }

    @Test func freshCatalogReResolutionMarksStaleWindowLost() {
        let old = RecordlySourceSelection.CatalogSnapshot.Window(number: 9, identityToken: "old", isPresent: true)
        let intent = RecordlySourceSelection.SelectionIntent.window(number: 9, identityToken: "old")
        let first = RecordlySourceSelection.resolve(intent: intent, in: .init(windows: [old]), permission: .granted)
        guard case .ready(let resolved) = first, let staleIntent = RecordlySourceSelection.intent(for: resolved) else {
            Issue.record("Expected initial source to resolve.")
            return
        }
        guard case .lostSource = RecordlySourceSelection.resolve(intent: staleIntent, in: .init(windows: [.init(number: 9, identityToken: "new", isPresent: true)]), permission: .granted) else {
            Issue.record("Stale identity must not bind to a reused window number.")
            return
        }
    }

    @Test func windowMappingSharesTokenAndPresenceSizeFilter() {
        let frame = CGRect(x: 2, y: 3, width: 80, height: 60)
        let binding = RecordlySourceSelection.windowBinding(number: 5, ownerProcessID: 12, title: "Editor", frame: frame, isOnScreen: true)
        #expect(binding?.number == 5)
        #expect(binding?.identityToken == "5:12")
        #expect(binding?.title == "Editor")
        #expect(binding?.isPresent == true)
        let movedOrRenamed = RecordlySourceSelection.windowBinding(
            number: 5,
            ownerProcessID: 12,
            title: "Renamed",
            frame: CGRect(x: -300, y: 40, width: 90, height: 70),
            isOnScreen: true
        )
        #expect(movedOrRenamed?.identityToken == binding?.identityToken)
        #expect(RecordlySourceSelection.windowBinding(number: 5, ownerProcessID: 12, title: "Editor", frame: CGRect(x: 0, y: 0, width: 20, height: 60), isOnScreen: true) == nil)
        #expect(RecordlySourceSelection.windowBinding(number: 5, ownerProcessID: 12, title: "Editor", frame: frame, isOnScreen: false) == nil)
        #expect(RecordlySourceSelection.windowBinding(number: 5, ownerProcessID: nil, title: "Editor", frame: frame, isOnScreen: true) == nil)
        #expect(RecordlySourceSelection.windowBinding(number: 0, ownerProcessID: 12, title: "Editor", frame: frame, isOnScreen: true) == nil)
    }

    @Test func duplicateWindowNumberIsAmbiguousAndNilOwnerCannotBind() {
        let intent = RecordlySourceSelection.SelectionIntent.window(number: 5, identityToken: "token")
        let duplicateCatalog = RecordlySourceSelection.CatalogSnapshot(windows: [
            .init(number: 5, identityToken: "token", isPresent: true),
            .init(number: 5, identityToken: "token", isPresent: true)
        ])
        guard case .invalidIntent(let reason) = RecordlySourceSelection.resolve(intent: intent, in: duplicateCatalog, permission: .granted) else {
            Issue.record("Duplicate window identities must fail closed.")
            return
        }
        #expect(reason.contains("ambiguous"))
        #expect(RecordlySourceSelection.windowBinding(number: 5, ownerProcessID: nil, title: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true) == nil)
    }

    @Test func invalidExplicitIdentityCannotEnableRecord() {
        #expect(!RecordlySourceSelection.hasValidExplicitIdentity(.display(id: 0)))
        #expect(!RecordlySourceSelection.hasValidExplicitIdentity(.window(number: 0, identityToken: "token")))
        #expect(!RecordlySourceSelection.hasValidExplicitIdentity(.window(number: -1, identityToken: "x")))
        #expect(!RecordlySourceSelection.hasValidExplicitIdentity(.region(displayID: 17, x: 0, y: 0, width: .infinity, height: 4)))
        #expect(!RecordlySourceSelection.hasValidExplicitIdentity(.region(displayID: 17, x: 0, y: 0, width: 10, height: 4)))
        #expect(RecordlySourceSelection.hasValidExplicitIdentity(.display(id: 17)))
    }

    @Test func injectedProviderLoadsSyntheticCatalogAndCanStartRequiresResolvedIdentity() async {
        var picker = RecordlySourcePicker()
        #expect(!picker.canStart)
        let generation = picker.beginLoading()
        #expect(picker.state == .loading(generation: generation))

        let provider = SyntheticCatalogProvider(result: .loaded(.init(displays: [displayA])))
        let result = await provider.loadCatalog()
        let didFinishLoading = picker.finishLoading(result, generation: generation)
        #expect(didFinishLoading)
        #expect(!picker.canStart)

        guard case .selected = picker.selectSource(.display(id: 17)) else {
            Issue.record("The exact loaded display should be selectable.")
            return
        }
        #expect(picker.canStart)

        picker.beginLoading()
        #expect(!picker.canStart)
    }

    @Test func olderCatalogGenerationCannotReplaceNewerLoadingState() {
        var picker = RecordlySourcePicker()
        let oldGeneration = picker.beginLoading()
        let currentGeneration = picker.beginLoading()

        let acceptedOldGeneration = picker.finishLoading(.loaded(.init(displays: [displayA])), generation: oldGeneration)
        #expect(!acceptedOldGeneration)
        #expect(picker.state == .loading(generation: currentGeneration))
        let acceptedCurrentGeneration = picker.finishLoading(.loaded(.init(displays: [displayA])), generation: currentGeneration)
        #expect(acceptedCurrentGeneration)
        #expect(picker.state == .loaded(snapshot: .init(displays: [displayA]), generation: currentGeneration))
        #expect(!picker.canStart)
    }

    @Test func duplicateDisplayIdentityIsRejectedAndCannotEnableRecord() {
        var picker = RecordlySourcePicker()
        let generation = picker.beginLoading()
        let didFinishLoading = picker.finishLoading(.loaded(.init(displays: [displayA, displayA])), generation: generation)
        #expect(didFinishLoading)

        guard case .rejected(let reason) = picker.selectSource(.display(id: 17)) else {
            Issue.record("Duplicate display identities must be rejected as ambiguous.")
            return
        }
        #expect(reason.contains("ambiguous"))
        #expect(!picker.canStart)
    }

    @Test func deniedAndFailedProvidersRemainDistinctAndDisableRecord() async {
        for result in [
            RecordlySourceCatalogLoadResult.denied(reason: "Permission denied."),
            .failed(reason: "Catalog failed.")
        ] {
            var picker = RecordlySourcePicker()
            let generation = picker.beginLoading()
            let provider = SyntheticCatalogProvider(result: result)
            let providerResult = await provider.loadCatalog()
            let didFinishLoading = picker.finishLoading(providerResult, generation: generation)
            #expect(didFinishLoading)
            #expect(!picker.canStart)
            switch (result, picker.state) {
            case (.denied(let expected), .denied(let actual)):
                #expect(actual == expected)
            case (.failed(let expected), .failed(let actual)):
                #expect(actual == expected)
            default:
                Issue.record("Provider denial and failure must remain truthful distinct states.")
            }
        }
    }

    @Test func refreshMarksRemovedSelectionStaleAndRequiresReselection() async {
        var picker = RecordlySourcePicker()
        let firstGeneration = picker.beginLoading()
        let initial = SyntheticCatalogProvider(result: .loaded(.init(displays: [displayA])))
        let initialResult = await initial.loadCatalog()
        let didFinishInitialLoad = picker.finishLoading(initialResult, generation: firstGeneration)
        #expect(didFinishInitialLoad)
        guard case .selected = picker.selectSource(.display(id: 17)) else {
            Issue.record("The starting display should resolve.")
            return
        }
        #expect(picker.canStart)

        let refreshGeneration = picker.beginLoading()
        let replacement = RecordlySourceSelection.CatalogSnapshot.Display(
            id: 29,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )
        let refreshed = SyntheticCatalogProvider(result: .loaded(.init(displays: [replacement])))
        let refreshedResult = await refreshed.loadCatalog()
        let didFinishRefresh = picker.finishLoading(refreshedResult, generation: refreshGeneration)
        #expect(didFinishRefresh)
        guard case .stale(let maybeSnapshot, let maybeGeneration, let reason) = picker.state,
              let snapshot = maybeSnapshot, let generation = maybeGeneration else {
            Issue.record("A removed selected display must produce a stale state.")
            return
        }
        #expect(snapshot.displays == [replacement])
        #expect(generation == refreshGeneration)
        #expect(!reason.isEmpty)
        #expect(!picker.canStart)
        guard case .selected = picker.selectSource(.display(id: 29)) else {
            Issue.record("A new exact display from the current catalog should be selectable.")
            return
        }
        #expect(picker.canStart)
    }

    @Test func pickerRejectsRegionOwnerlessWindowAndInvalidIdentities() {
        var picker = RecordlySourcePicker()
        let windowFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
        let ownedWindow = RecordlySourceSelection.windowBinding(
            number: 21,
            ownerProcessID: 42,
            title: "Editor",
            frame: windowFrame,
            isOnScreen: true,
            ownerName: "Example"
        )!
        #expect(RecordlySourceSelection.windowBinding(
            number: 22,
            ownerProcessID: nil,
            title: "Ownerless",
            frame: windowFrame,
            isOnScreen: true
        ) == nil)

        let generation = picker.beginLoading()
        let didFinishLoading = picker.finishLoading(.loaded(.init(displays: [displayA], windows: [ownedWindow])), generation: generation)
        #expect(didFinishLoading)
        guard case .selected = picker.selectSource(.window(number: 21, identityToken: "21:42")) else {
            Issue.record("An owned exact window should be selectable.")
            return
        }
        #expect(picker.canStart)

        guard case .rejected = picker.selectSource(.region(displayID: 17, x: 1, y: 2, width: 30, height: 40)) else {
            Issue.record("Region must stay rejected until its coordinate contract is established.")
            return
        }
        #expect(!picker.canStart)
        guard case .rejected = picker.selectSource(.display(id: 0)) else {
            Issue.record("Display id 0 must not enable Record.")
            return
        }
        #expect(!picker.canStart)
    }

    @Test func engineInvalidationClearsCurrentCatalogAndSelection() async {
        var picker = RecordlySourcePicker()
        let generation = picker.beginLoading()
        let provider = SyntheticCatalogProvider(result: .loaded(.init(displays: [displayA])))
        let providerResult = await provider.loadCatalog()
        let didFinishLoading = picker.finishLoading(providerResult, generation: generation)
        #expect(didFinishLoading)
        guard case .selected = picker.selectSource(.display(id: 17)) else {
            Issue.record("The display should be selected before engine invalidation.")
            return
        }
        picker.markStale(reason: "The selected display is no longer available.")
        #expect(picker.catalog == nil)
        #expect(picker.selectionIntent == nil)
        #expect(!picker.canStart)
        guard case .stale(nil, nil, let reason) = picker.state else {
            Issue.record("Engine revalidation failure should leave the picker stale until refresh.")
            return
        }
        #expect(reason.contains("no longer available"))
    }

    private func resolve(
        _ intent: RecordlySourceSelection.SelectionIntent,
        displays: [RecordlySourceSelection.CatalogSnapshot.Display] = [],
        windows: [RecordlySourceSelection.CatalogSnapshot.Window] = []
    ) -> RecordlySourceSelection.Outcome {
        RecordlySourceSelection.resolve(
            intent: intent,
            in: .init(displays: displays, windows: windows),
            permission: .granted
        )
    }
}

private struct SyntheticCatalogProvider: RecordlySourceCatalogProvider {
    let result: RecordlySourceCatalogLoadResult

    func loadCatalog() async -> RecordlySourceCatalogLoadResult {
        result
    }
}
