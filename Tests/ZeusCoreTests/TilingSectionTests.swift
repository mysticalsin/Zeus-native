import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

private func id(_ n: Int, pid: Int32 = 700) -> TileWindowID { TileWindowID(pid: pid, index: n) }

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TileRect {
    TileRect(x: x, y: y, width: w, height: h)
}

/// A 1440 x 900 main display with a 24 point menu bar. The usable height is even, so two stacked tiles come out the same height.
private func mainDisplay(id: UInt32 = 1) -> TileDisplay {
    TileDisplay(id: id, appKitFrame: rect(0, 0, 1440, 900), appKitVisibleFrame: rect(0, 0, 1440, 876),
                engineFrame: rect(0, 0, 1440, 900))
}

/// A 1920 x 1080 display to the left of the main one.
private func leftDisplay(id: UInt32 = 2) -> TileDisplay {
    let appKit = rect(-1920, 0, 1920, 1080)
    return TileDisplay(id: id, appKitFrame: appKit, appKitVisibleFrame: rect(-1920, 0, 1920, 1055),
                       engineFrame: TileDisplay.engineFrame(appKitFrame: appKit, mainScreenHeight: 900))
}

/// Three windows on the main display, tiled the way the engine does: 1 on the left, 2 above 3 on the right.
private func threeWindowState(focused: TileWindowID? = id(1), recency: [TileWindowID] = []) -> TileLayoutState {
    let display = mainDisplay()
    let config = TileConfig()
    let result = TileOps.reconcile(tree: TileTree(displayID: display.id), eligible: [id(1), id(2), id(3)],
                                   order: [id(1), id(2), id(3)], display: display.visibleFrame, config: config)
    return TileLayoutState(trees: [display.id: result.tree], floating: [], focused: focused, recency: recency)
}

/// The parent of every section suite, so one filter, `TilingSectionTests`, runs them all.
@Suite struct TilingSectionTests {}

// MARK: Tab, row and startup

extension TilingSectionTests {
    @Suite struct TabTests {
        @Test func theTilingTabIsAppendedLastWithItsWordsAndSymbol() {
            #expect(TopBarTab.allCases.last == .tiling)
            #expect(TopBarTab.allCases.dropLast().last == .waves)
            #expect(TopBarTab.tiling.title == "Tiling")
            #expect(TopBarTab.tiling.symbol == "rectangle.split.2x2.fill")
            #expect(TopBarTab.tiling.help == "Tiling: arrange your windows from the keyboard")
            #expect(TopBarTab(rawValue: "tiling") == .tiling)
        }

        @Test func theTilingTabIsSecondInTheDefaultRowRightAfterHome() {
            #expect(TopBarLayout.defaultRow[0] == .home)
            #expect(TopBarLayout.defaultRow[1] == .tiling)
            #expect(TopBarLayout.defaultRow[2] == .agents)
            #expect(TopBarLayout.defaultRow.count == 14)
            #expect(TopBarLayout.standard.tabs.prefix(14).elementsEqual(TopBarLayout.defaultRow))
            #expect(GlanceTabRow.visible(TopBarLayout.standard.tabs, selected: .home) == TopBarLayout.defaultRow)
        }

        @Test func theRowHoldsFourteenTabsAtEightPointSpacing() {
            #expect(GlanceTopBar.maxTabs == 14)
            #expect(GlanceTopBar.tabSpacing == 8)
            #expect(GlanceTopBar.plainTabSlot == 43)
            // 2 x 5.5 + 82 + 13 x 43 (13 pt icon, 11 pt padding either side, 8 pt apart).
            #expect(Double(GlanceTopBar.capsuleWidth(tabs: 14)) == 652)
        }

        @Test func fourteenTabsFitTheRowEvenWithTheWidestLabelAndThreeBigCounts() {
            let widest = TopBarLayout.defaultRow.map { GlanceTopBar.selectedPillWidth(title: $0.title, countWidth: 26) }.max() ?? 0
            let worst = GlanceTopBar.capsuleWidth(tabs: 14, countsExtra: 3 * 26 + widest - GlanceTopBar.selectedPill.width)
            #expect(worst < GlanceTopBar.rowRoom, "worst case \(worst) of \(GlanceTopBar.rowRoom)")
        }

        @Test func aFifteenthTabStaysOffTheRowAndTheSelectedOneTakesTheLastSlot() {
            let tabs = Array(1...15)
            #expect(GlanceTabRow.visible(tabs, selected: 3) == Array(1...14))
            #expect(GlanceTabRow.visible(tabs, selected: 15) == Array(1...13) + [15])
        }

        @Test func theTilingUpgradePutsTilingRightAfterHomeAndIsIdempotent() {
            let saved = TopBarLayout(tabs: [.home, .agents, .chat, .notifications, .clipboard, .shelf, .todo, .dictation, .teleprompter,
                                            .insomnia, .polyglot, .recordly, .scribe, .reminders, .usage])
            let upgraded = saved.upgradedToTilingRow()
            #expect(Array(upgraded.tabs.prefix(14)) == TopBarLayout.defaultRow)
            #expect(upgraded.upgradedToTilingRow() == upgraded)
            #expect(GlanceTabRow.visible(upgraded.tabs, selected: .home).contains(.tiling))
        }

        @Test func theTilingUpgradeKeepsTabsThePersonTurnedOff() {
            let custom = TopBarLayout(tabs: [.home, .chat, .agents])
            #expect(custom.upgradedToTilingRow().tabs == [.home, .tiling, .agents, .chat])
            #expect(!custom.upgradedToTilingRow().contains(.clipboard))
        }

        @Test func aTilingRowThePersonTurnedOffStaysOff() {
            var layout = TopBarLayout.standard
            layout.toggle(.tiling)
            #expect(!layout.contains(.tiling))
            let saved = TopBarLayout.decode(layout.encoded(), known: TopBarLayout.knownEncoded())
            #expect(!saved.contains(.tiling))
        }

        @Test func switchingTilingBackOnReturnsItToItsPlaceAndNoOtherTabJumpsBeforeIt() {
            var layout = TopBarLayout.standard
            layout.toggle(.tiling)
            layout.toggle(.tiling)
            #expect(layout.tabs[1] == .tiling)
            // A tab switched back on keeps its usual place after Tiling, not in front of it.
            layout.toggle(.music)
            layout.toggle(.music)
            #expect(layout.tabs[1] == .tiling)
            let music = layout.tabs.firstIndex(of: .music)
            let tiling = layout.tabs.firstIndex(of: .tiling)
            #expect(music != nil && tiling != nil && music! > tiling!)
        }

        @Test func aLayoutSavedBeforeTilingShowsItInItsPlace() {
            let knownBefore = TopBarTab.allCases.filter { $0 != .tiling }.map(\.rawValue)
            let known = String(decoding: try! JSONEncoder().encode(knownBefore), as: UTF8.self)
            let layout = TopBarLayout.decode(#"["home","chat"]"#, known: known)
            #expect(layout.contains(.tiling))
        }

        @Test func theLayoutRepairSwitchesTilingOnForARowThatSavedItsFlagWithoutTheRow() {
            #expect(TopBarLayoutRepair.upgradeTabs.contains(.tiling))
            #expect(TopBarLayoutRepair.version == 2)
            let old = TopBarLayout(tabs: TopBarLayout.glanceSeven)
            let repaired = TopBarLayoutRepair.repaired(old, savedKnown: nil)
            #expect(repaired.contains(.tiling))
            #expect(repaired.tabs[1] == .tiling)
            // A person who removed it while the build knew it keeps it removed.
            let known = TopBarLayout.knownEncoded()
            #expect(!TopBarLayoutRepair.repaired(TopBarLayout(tabs: TopBarLayout.glanceSeven), savedKnown: known).contains(.tiling))
        }
    }

    @Suite struct StartupTests {
        @Test func aQAStartupDeniesTiling() {
            #expect(StartupService.allCases.contains(.tiling))
            #expect(StartupPolicy.normal.allows(.tiling))
            #expect(!StartupPolicy(mode: .qa(root: "/tmp/zeus-qa-x")).allows(.tiling))
            #expect(!StartupPolicy(mode: .invalid(reason: "x")).allows(.tiling))
            #expect(!StartupPolicy.qaAllowed.contains(.tiling))
        }
    }
}

// MARK: Phase

extension TilingSectionTests {
    @Suite struct PhaseTests {
        @Test func theSwitchDecidesBeforeAnythingElse() {
            #expect(TilingPhase(enabled: false, accessibilityOn: false, keysUnavailable: true, paused: true) == .off)
            #expect(TilingPhase(enabled: false, accessibilityOn: true, keysUnavailable: false, paused: false) == .off)
        }

        @Test func accessibilityComesBeforeTheKeysAndThePause() {
            #expect(TilingPhase(enabled: true, accessibilityOn: false, keysUnavailable: true, paused: true) == .needsAccessibility)
            #expect(TilingPhase(enabled: true, accessibilityOn: true, keysUnavailable: true, paused: true) == .keysUnavailable)
            #expect(TilingPhase(enabled: true, accessibilityOn: true, keysUnavailable: false, paused: true) == .paused)
            #expect(TilingPhase(enabled: true, accessibilityOn: true, keysUnavailable: false, paused: false) == .running)
        }

        @Test func aKeyClashComesAfterTheSwitchAndBeforeEverythingElse() {
            #expect(TilingPhase(enabled: false, accessibilityOn: true, keysUnavailable: false, paused: false, keyClash: true) == .off)
            #expect(TilingPhase(enabled: true, accessibilityOn: false, keysUnavailable: true, paused: true, keyClash: true) == .keyClash)
            #expect(TilingPhase(enabled: true, accessibilityOn: true, keysUnavailable: false, paused: false, keyClash: true) == .keyClash)
            #expect(TilingPhase(enabled: true, accessibilityOn: true, keysUnavailable: false, paused: false) == .running,
                    "no clash by default")
        }

        @Test func everyStateHasItsOwnWordAndItsOwnSymbolSoColourIsNeverTheOnlyCue() {
            let phases: [TilingPhase] = [.off, .needsAccessibility, .keyClash, .keysUnavailable, .paused, .running]
            #expect(Set(phases.map(\.word)).count == phases.count)
            #expect(Set(phases.map(\.symbol)).count == phases.count)
            #expect(phases.allSatisfy { !$0.detail.isEmpty })
            #expect(TilingPhase.running.isActive)
            #expect(phases.filter(\.isActive) == [.running])
        }

        @Test func theCopyIsPlainAndHasNoDashes() {
            let phases: [TilingPhase] = [.off, .needsAccessibility, .keyClash, .keysUnavailable, .paused, .running]
            for phase in phases {
                for text in [phase.word, phase.detail] {
                    #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)")
                }
            }
        }
    }

    @Suite struct GenerationTests {
        @Test func advancingMakesEarlierTokensStale() {
            var generation = TileGeneration()
            let first = generation.advance()
            #expect(generation.isCurrent(first))
            let second = generation.advance()
            #expect(!generation.isCurrent(first))
            #expect(generation.isCurrent(second))
            #expect(second > first)
        }

        @Test func aFreshCounterHasNoCurrentTokenForAWorkItemFromBeforeItExisted() {
            let generation = TileGeneration()
            #expect(!generation.isCurrent(-1))
            #expect(generation.isCurrent(generation.value))
        }
    }
}

// MARK: Resolving a key action

extension TilingSectionTests {
    @Suite struct ResolverTests {
        private func resolve(_ action: TileAction, _ state: TileLayoutState, displays: [TileDisplay] = [mainDisplay()]) -> (state: TileLayoutState, effect: TileEffect) {
            TileResolver.resolve(action, in: state, displays: displays, config: TileConfig())
        }

        @Test func focusMovesToTheNearestWindowThatWayAndRemembersIt() {
            let result = resolve(.focus(.right), threeWindowState())
            #expect(result.effect == .focus(id(2)), "windows 2 and 3 overlap window 1 equally and sit the same distance away, so the lower id wins")
            #expect(result.state.focused == id(2))
            #expect(result.state.recency.first == id(2))
            #expect(result.state.trees == threeWindowState().trees, "moving focus never edits the tree")
        }

        @Test func recencyBreaksATieBetweenEquallyGoodNeighbours() {
            let result = resolve(.focus(.right), threeWindowState(recency: [id(3), id(2)]))
            #expect(result.effect == .focus(id(3)))
        }

        @Test func focusWithNothingThatWayDoesNothing() {
            let state = threeWindowState()
            let result = resolve(.focus(.left), state)
            #expect(result.effect == .none)
            #expect(result.state == state)
        }

        @Test func focusFromAWindowThatIsNotTiledGoesBackToTheLastTiledOne() {
            let floatingWindow = id(9)
            var state = threeWindowState(focused: floatingWindow, recency: [id(3), id(1)])
            state.floating = [floatingWindow]
            let result = resolve(.focus(.left), state)
            #expect(result.effect == .focus(id(3)))
            // With no history it falls to the first tiled window.
            let fresh = resolve(.focus(.up), threeWindowState(focused: nil))
            #expect(fresh.effect == .focus(id(1)))
        }

        @Test func focusWithNoTiledWindowDoesNothing() {
            let result = resolve(.focus(.left), TileLayoutState())
            #expect(result.effect == .none)
        }

        @Test func swapExchangesTwoSlotsKeepsFocusAndAsksForALayout() {
            let before = threeWindowState()
            let result = resolve(.swap(.right), before)
            #expect(result.effect == .relayout)
            #expect(result.state.focused == id(1), "focus stays on the window that moved")
            let tree = try! #require(result.state.trees[1])
            #expect(tree.windows == [id(2), id(1), id(3)])
            #expect(tree.order == before.trees[1]!.order.map { $0 == id(1) ? id(2) : ($0 == id(2) ? id(1) : $0) })
        }

        @Test func swapWithNoNeighbourDoesNothing() {
            let state = threeWindowState()
            let result = resolve(.swap(.left), state)
            #expect(result.effect == .none)
            #expect(result.state == state)
        }

        @Test func swapNeverCrossesToAnotherDisplay() {
            // One window on each display: the neighbour to the left is on the other display, which this slice does not send windows to.
            let main = mainDisplay(), left = leftDisplay()
            var state = TileLayoutState()
            state.trees[main.id] = TileTree(displayID: main.id, root: .leaf(window: id(1)), order: [id(1)])
            state.trees[left.id] = TileTree(displayID: left.id, root: .leaf(window: id(2)), order: [id(2)])
            state.focused = id(1)
            let result = resolve(.swap(.left), state, displays: [main, left])
            #expect(result.effect == .none)
            #expect(result.state == state)
            // Focus does cross displays: it only moves the keyboard.
            #expect(resolve(.focus(.left), state, displays: [main, left]).effect == .focus(id(2)))
        }

        @Test func flipTurnsTheParentSplitAndAsksForALayout() {
            let result = resolve(.flipSplit, threeWindowState(focused: id(2)))
            #expect(result.effect == .relayout)
            #expect(result.state.trees[1] != threeWindowState().trees[1])
            #expect(resolve(.flipSplit, result.state).state.trees[1] != result.state.trees[1], "a second flip turns it back")
        }

        @Test func flipOnALoneWindowDoesNothing() {
            var state = TileLayoutState()
            state.trees[1] = TileTree(displayID: 1, root: .leaf(window: id(1)), order: [id(1)])
            state.focused = id(1)
            let result = resolve(.flipSplit, state)
            #expect(result.effect == .none)
            #expect(result.state == state)
        }

        @Test func nudgeMovesTheNearestSplitByFivePointsOfAHundred() {
            let result = resolve(.nudge(.right), threeWindowState())
            #expect(result.effect == .relayout)
            guard case .split(_, let ratio, _, _, _)? = result.state.trees[1]?.root else {
                Issue.record("the root should still be a split")
                return
            }
            #expect(abs(ratio - 0.55) < 1e-9)
        }

        @Test func severalNudgesAreOneResolveWithOneLayoutRequest() {
            let once = resolve(.nudge(.right), threeWindowState())
            let twice = resolve(.nudge(.right), once.state)
            let batched = TileResolver.resolve(.nudge(.right), times: 2, in: threeWindowState(), displays: [mainDisplay()], config: TileConfig())
            #expect(batched.state == twice.state, "two steps give what two single nudges give")
            #expect(batched.effect == .relayout)
            guard case .split(_, let ratio, _, _, _)? = batched.state.trees[1]?.root else {
                Issue.record("the root should still be a split")
                return
            }
            #expect(abs(ratio - 0.60) < 1e-9)
        }

        @Test func aLongRunOfNudgesStopsAtTheRatioLimit() {
            let batched = TileResolver.resolve(.nudge(.right), times: TileActionMailbox.maxNudgeSteps, in: threeWindowState(),
                                               displays: [mainDisplay()], config: TileConfig())
            guard case .split(_, let ratio, _, _, _)? = batched.state.trees[1]?.root else {
                Issue.record("the root should still be a split")
                return
            }
            #expect(abs(ratio - TileRatio.maximum) < 1e-9)
            #expect(batched.effect == .relayout)
        }

        @Test func aRepeatCountMeansNothingToAnyOtherAction() {
            for action in [TileAction.focus(.right), .swap(.right), .flipSplit, .retile, .toggleFloat] {
                let single = resolve(action, threeWindowState(focused: id(2)))
                let counted = TileResolver.resolve(action, times: 9, in: threeWindowState(focused: id(2)), displays: [mainDisplay()], config: TileConfig())
                #expect(counted.state == single.state && counted.effect == single.effect, "\(action)")
            }
        }

        @Test func nudgesWithNothingToMoveStayNothing() {
            let state = threeWindowState()
            let batched = TileResolver.resolve(.nudge(.left), times: 5, in: state, displays: [mainDisplay()], config: TileConfig())
            #expect(batched.effect == .none && batched.state == state)
        }

        @Test func nudgeWithNoMatchingSplitDoesNothing() {
            // Window 1 is the left column: only a split on its right edge can move, so nudging it left finds none.
            let state = threeWindowState()
            let result = resolve(.nudge(.left), state)
            #expect(result.effect == .none)
            #expect(result.state == state)
        }

        @Test func toggleFloatTakesTheWindowOutOfItsTreeAndBack() {
            let out = resolve(.toggleFloat, threeWindowState(focused: id(2)))
            #expect(out.effect == .relayout)
            #expect(out.state.floating == [id(2)])
            #expect(out.state.trees[1]?.windows == [id(1), id(3)])
            #expect(out.state.focused == id(2))

            let back = resolve(.toggleFloat, out.state)
            #expect(back.effect == .relayout)
            #expect(back.state.floating.isEmpty, "the next layout pass puts it back in the tree")
        }

        @Test func toggleFloatOnAWindowTheLayoutDoesNotKnowDoesNothing() {
            let state = threeWindowState(focused: id(42))
            let result = resolve(.toggleFloat, state)
            #expect(result.effect == .none)
            #expect(result.state == state)
            #expect(resolve(.toggleFloat, threeWindowState(focused: nil)).effect == .none)
        }

        @Test func theOtherActionsPassStraightThrough() {
            let state = threeWindowState()
            let expected: [(TileAction, TileEffect)] = [(.retile, .relayout), (.togglePause, .togglePause),
                                                       (.showKeys, .showKeys), (.maximizeToggle, .none)]
            for (action, effect) in expected {
                let result = resolve(action, state)
                #expect(result.effect == effect, "\(action.id)")
                #expect(result.state == state, "\(action.id) never edits the layout")
            }
        }

        @Test func resolvingIsDeterministic() {
            let state = threeWindowState(recency: [id(2), id(3)])
            for action in TileAction.all {
                let a = resolve(action, state), b = resolve(action, state)
                #expect(a.state == b.state && a.effect == b.effect, "\(action.id)")
            }
        }
    }
}

// MARK: The layout picture

extension TilingSectionTests {
    @Suite struct PictureTests {
        @Test func twoWindowsDrawAsTwoTilesInsideOneDisplayAndTheFocusedOneIsMarked() {
            let display = mainDisplay()
            let result = TileOps.reconcile(tree: TileTree(displayID: 1), eligible: [id(1), id(2)], order: [id(1), id(2)],
                                           display: display.visibleFrame, config: TileConfig())
            let picture = TilingPicture.make(displays: [display], trees: [1: result.tree], config: TileConfig(), focused: id(2))
            #expect(picture.count == 1)
            #expect(abs(picture[0].aspect - 1440.0 / 900.0) < 1e-9)
            #expect(picture[0].tiles.map(\.window) == [id(1), id(2)])
            #expect(picture[0].tiles.map(\.isFocused) == [false, true])
            for tile in picture[0].tiles {
                #expect(tile.rect.minX >= 0 && tile.rect.maxX <= 1 && tile.rect.minY >= 0 && tile.rect.maxY <= 1)
            }
            #expect(picture[0].tiles[0].rect.maxX < picture[0].tiles[1].rect.minX, "the gap shows between the tiles")
            #expect(picture[0].tiles[0].rect.minY > 0, "the menu bar and the outer gap show above the tiles")
        }

        @Test func displaysAreOrderedLeftToRightAndAnEmptyOneStillDraws() {
            let main = mainDisplay(), left = leftDisplay()
            let picture = TilingPicture.make(displays: [main, left], trees: [:], config: TileConfig(), focused: nil)
            #expect(picture.map(\.displayID) == [2, 1], "the display to the left comes first")
            #expect(picture.allSatisfy { $0.tiles.isEmpty })
        }

        @Test func aTreeForADisplayThatIsGoneIsNotDrawn() {
            let main = mainDisplay()
            let tree = TileTree(displayID: 7, root: .leaf(window: id(1)), order: [id(1)])
            let picture = TilingPicture.make(displays: [main], trees: [7: tree], config: TileConfig(), focused: nil)
            #expect(picture.count == 1 && picture[0].tiles.isEmpty)
        }

        @Test func aDisplayWithNoSizeIsLeftOut() {
            let flat = TileDisplay(id: 5, appKitFrame: rect(0, 0, 0, 0), appKitVisibleFrame: rect(0, 0, 0, 0), engineFrame: rect(0, 0, 0, 0))
            #expect(TilingPicture.make(displays: [flat], trees: [:], config: TileConfig(), focused: nil).isEmpty)
        }

        @Test func aFocusedWindowThatIsNotTiledMarksNothing() {
            let display = mainDisplay()
            let tree = TileTree(displayID: 1, root: .leaf(window: id(1)), order: [id(1)])
            let picture = TilingPicture.make(displays: [display], trees: [1: tree], config: TileConfig(), focused: id(9))
            #expect(picture[0].tiles.map(\.isFocused) == [false])
        }

        @Test func thePictureCarriesNoWindowTitleOrApp() {
            let mirror = Mirror(reflecting: TilingPictureTile(window: id(1), rect: rect(0, 0, 1, 1), isFocused: false))
            let names = mirror.children.compactMap(\.label)
            #expect(names == ["window", "rect", "isFocused"])
        }
    }
}

// MARK: The key list

extension TilingSectionTests {
    @Suite struct KeyListTests {
        @Test func theDefaultKeymapReadsAsEightShortRows() {
            let rows = TileKeyList.rows(keymap: TileKeymap.defaults(base: .controlOption))
            #expect(rows.map(\.title) == ["Move focus", "Swap windows", "Flip the split", "Float or tile", "Pause or resume",
                                          "Retile", "Resize the split", "Show these keys"])
            #expect(rows.map(\.keys) == ["⌃⌥ ← → ↑ ↓", "⌃⌥⇧ ← → ↑ ↓", "⌃⌥ J", "⌃⌥ T", "⌃⌥ P", "⌃⌥ R", "⌃⌥⇧ [ ]", "⌃⌥ K"])
        }

        @Test func theRowsFollowTheChosenBase() {
            let rows = TileKeyList.rows(keymap: TileKeymap.defaults(base: .optionCommand))
            #expect(rows.first?.keys == "⌥⌘ ← → ↑ ↓")
            #expect(TileKeyList.rows(keymap: TileKeymap.defaults(base: .controlOptionCommand)).last?.keys == "⌃⌥⌘ K")
        }

        @Test func everyRowHasAnSpokenFormThatNamesTheModifiersInWords() {
            let rows = TileKeyList.rows(keymap: TileKeymap.defaults(base: .controlOption))
            #expect(rows.allSatisfy { !$0.spoken.isEmpty })
            #expect(rows[0].spoken == "Control + Option with Left Arrow, Right Arrow, Up Arrow, Down Arrow")
            #expect(rows[2].spoken == "Control + Option with J")
            #expect(rows[6].spoken == "Control + Option + Shift with Left Bracket, Right Bracket")
        }

        @Test func aRowThatNoKeyIsBoundToIsLeftOut() {
            #expect(TileKeyList.rows(keymap: TileKeymap()).isEmpty)
            var map = TileKeymap()
            try? map.bind(Shortcut(keyCode: 40, modifiers: [.control, .option]), to: .showKeys)
            #expect(TileKeyList.rows(keymap: map).map(\.title) == ["Show these keys"])
        }

        @Test func chordsWithDifferentModifiersAreListedOneByOne() {
            var map = TileKeymap()
            try? map.bind(Shortcut(keyCode: 123, modifiers: [.control, .option]), to: .focus(.left))
            try? map.bind(Shortcut(keyCode: 124, modifiers: [.option, .command]), to: .focus(.right))
            #expect(TileKeyList.rows(keymap: map).first?.keys == "⌃⌥← ⌥⌘→")
        }

        @Test func everyDefaultBoundActionAppearsInSomeRow() {
            let keymap = TileKeymap.defaults(base: .controlOption)
            let rows = TileKeyList.rows(keymap: keymap)
            #expect(rows.count == 8)
            for binding in keymap.bindings {
                #expect(rows.contains { $0.keys.contains(Shortcut.keyName(binding.shortcut.keyCode ?? 0)) }, "\(binding.action.id)")
            }
        }

        @Test func theWordsHaveNoDashes() {
            for row in TileKeyList.rows(keymap: TileKeymap.defaults(base: .controlOption)) {
                for text in [row.title, row.spoken] { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}")) }
            }
        }
    }
}

// MARK: The config from settings

extension TilingSectionTests {
    @Suite struct SettingsConfigTests {
        private func isolated() throws -> (UserDefaults, cleanup: () -> Void) {
            let name = "zeus.tiling.section.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.removePersistentDomain(forName: name)
            return (defaults, { defaults.removePersistentDomain(forName: name) })
        }

        @Test func aFreshInstallIsOffAndEqualsTheEngineDefaults() throws {
            let (defaults, cleanup) = try isolated()
            defer { cleanup() }
            #expect(TileConfig.fromSettings(defaults: defaults) == TileConfig.defaults)
            #expect(!TileConfig.fromSettings(defaults: defaults).enabled)
        }

        @Test func theSplitPercentageBecomesTheEngineRatio() throws {
            let (defaults, cleanup) = try isolated()
            defer { cleanup() }
            defaults.set("30", forKey: "opt.tiling.splitRatio")
            #expect(abs(TileConfig.fromSettings(defaults: defaults).defaultRatio - 0.30) < 1e-9)
            defaults.set("70", forKey: "opt.tiling.splitRatio")
            #expect(abs(TileConfig.fromSettings(defaults: defaults).defaultRatio - 0.70) < 1e-9)
            defaults.set("5", forKey: "opt.tiling.splitRatio")
            #expect(TileConfig.fromSettings(defaults: defaults).defaultRatio == TileRatio.minimum, "the engine clamp is the backstop")
        }

        @Test func everyStoredValueReachesTheConfig() throws {
            let (defaults, cleanup) = try isolated()
            defer { cleanup() }
            defaults.set("true", forKey: "opt.tiling.enabled")
            defaults.set("16", forKey: "opt.tiling.innerGap")
            defaults.set("4", forKey: "opt.tiling.outerGap")
            defaults.set("Option-Command", forKey: "opt.tiling.keyBase")
            defaults.set("com.example.One\ncom.example.Two", forKey: "opt.tiling.excludedApps")
            let config = TileConfig.fromSettings(defaults: defaults)
            #expect(config.enabled)
            #expect(!config.paused, "a pause is never stored")
            #expect(config.innerGap == 16 && config.outerGap == 4)
            #expect(config.base == .optionCommand)
            #expect(config.excludedBundleIDs == ["com.example.One", "com.example.Two"])
            #expect(config.floating.isEmpty)
        }

        @Test func aWrongStoredValueFallsBackToTheDefaultOrTheClamp() throws {
            let (defaults, cleanup) = try isolated()
            defer { cleanup() }
            defaults.set("wide", forKey: "opt.tiling.innerGap")
            defaults.set("500", forKey: "opt.tiling.outerGap")
            defaults.set("Hyper", forKey: "opt.tiling.keyBase")
            let config = TileConfig.fromSettings(defaults: defaults)
            #expect(config.innerGap == TileConfig.defaultGap)
            #expect(config.outerGap == 64)
            #expect(config.base == .controlOptionCommand)
        }
    }
}

// MARK: The frontmost window

extension TilingSectionTests {
    @Suite struct FrontmostTests {
        @Test func theEmptyAnswerNamesNoWindowAndIsNotFullScreen() {
            #expect(TileFrontmost.none.focused == nil)
            #expect(!TileFrontmost.none.isFullScreen)
        }
    }
}

// MARK: Key base words

extension TilingSectionTests {
    @Suite struct KeyBaseTests {
        @Test func theLabelsAreTheWordsTheSettingsRowStoresAndEachOneReadsBack() {
            #expect(TileModifierBase.allCases.map(\.label) == ["Control-Option", "Option-Command", "Control-Option-Command"])
            for base in TileModifierBase.allCases { #expect(TileModifierBase(label: base.label) == base) }
        }

        @Test func theShortFormUsesTheModifierGlyphs() {
            #expect(TileModifierBase.allCases.map(\.glyphs) == ["⌃⌥", "⌥⌘", "⌃⌥⌘"])
        }
    }
}
