import Testing
@testable import Zeus

@Suite("Lock space")
struct LockSpaceTests {
    @Test func oneMissingNameDropsTheTableAndNamesIt() {
        #expect(LockSpaceCatalog.symbolNames.count == 7)
        #expect(Set(LockSpaceCatalog.symbolNames).count == 7)
        for name in LockSpaceCatalog.symbolNames {
            let host = LiveLockSpace.hosting { lookedUp in
                lookedUp == name ? nil : symbolStandIn()
            }
            #expect(host.symbolsLoaded == false)
            #expect(host.missingSymbols() == [name])
            #expect(host.makeSpace() == false)
            #expect(host.attach(windowNumber: 4) == false)
            #expect(host.show() == false)
            #expect(host.hide() == false)
            #expect(host.destroy() == false)
            #expect(host.invocations == 0)
        }
    }

    @Test func everyNameMissingListsTheWholeTable() {
        let host = LiveLockSpace.hosting { _ in nil }
        #expect(host.symbolsLoaded == false)
        #expect(host.missingSymbols() == LockSpaceCatalog.symbolNames)
        #expect(host.removalCandidateResolved() == false)
        #expect(host.makeSpace() == false)
        #expect(host.invocations == 0)
    }

    @Test func anUnloadedHostKeepsNoPointer() {
        let host = LiveLockSpace.unloaded()
        #expect(host.symbolsLoaded == false)
        #expect(host.missingSymbols() == LockSpaceCatalog.symbolNames)
        #expect(host.removalCandidateResolved() == false)
        #expect(host.show() == false)
        #expect(host.hide() == false)
        #expect(host.destroy() == false)
        #expect(host.invocations == 0)
    }

    @Test func allSevenPresentKeepsTheTableAndCallsNothing() {
        let host = LiveLockSpace.hosting { _ in symbolStandIn() }
        #expect(host.symbolsLoaded)
        #expect(host.missingSymbols().isEmpty)
        #expect(host.removalCandidateResolved())
        #expect(host.invocations == 0)
        #expect(host.attach(windowNumber: 0) == false)
        #expect(host.attach(windowNumber: -3) == false)
        #expect(host.invocations == 0)
    }

    @Test func aMissingRemovalNameDoesNotDropTheTable() {
        let host = LiveLockSpace.hosting { name in
            name == LockSpaceCatalog.removalCandidate ? nil : symbolStandIn()
        }
        #expect(host.symbolsLoaded)
        #expect(host.missingSymbols().isEmpty)
        #expect(host.removalCandidateResolved() == false)
        #expect(host.invocations == 0)
    }

    @Test func theCatalogHoldsTheUnverifiedConstants() {
        #expect(LockSpaceCatalog.createFlag == 1)
        #expect(LockSpaceCatalog.level == 400)
        #expect(LockSpaceCatalog.moveSelector == 7)
        #expect(LockSpaceCatalog.frameworkPath.hasPrefix("/System/Library/PrivateFrameworks/"))
        #expect(LockSpaceCatalog.frameworkPath.hasSuffix("/SkyLight"))
        #expect(LockSpaceCatalog.frameworkPath.contains(".framework/"))
    }
}

/// A non-nil stand-in. Tests never call through it, so the address is not read.
private func symbolStandIn() -> UnsafeMutableRawPointer? {
    UnsafeMutableRawPointer(bitPattern: 1)
}
