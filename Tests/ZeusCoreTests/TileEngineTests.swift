import Foundation
import Testing
@testable import ZeusCore

private func id(_ n: Int) -> TileWindowID { TileWindowID(pid: 100, index: n) }

private let wide = TileRect(x: 0, y: 0, width: 1920, height: 1080)

/// Gaps of 16 and 8 on a 1920 x 1080 display give a usable area of (16, 16, 1888, 1048) and whole-number
/// frames, so the expected rectangles below are exact.
private func config(inner: Double = 8, outer: Double = 16, maxDepth: Int = 3, minTile: Double = 200,
                    ratio: Double = 0.5, floating: Set<TileWindowID> = []) -> TileConfig {
    TileConfig(innerGap: inner, outerGap: outer, maxDepth: maxDepth, minTileSize: minTile, defaultRatio: ratio,
               floating: floating)
}

/// Inserts windows 1...count in order with nothing focused. Fails the test when one is refused.
private func build(_ count: Int, display: TileRect = wide, config: TileConfig = config()) -> TileTree {
    var tree = TileTree(displayID: 1)
    for n in 1...max(count, 1) where count > 0 {
        guard case .inserted(let next) = TileOps.insert(id(n), into: tree, focused: nil, display: display, config: config) else {
            Issue.record("window \(n) was refused")
            return tree
        }
        tree = next
    }
    return tree
}

private func frames(_ tree: TileTree, display: TileRect = wide, config: TileConfig = config()) -> [TileWindowID: TileRect] {
    TileFrames.frames(of: tree, display: display, config: config)
}

/// The tree with the window ids erased: axis, ratio and pin of every split.
private func shape(_ node: TileNode) -> String {
    switch node {
    case .leaf: "L"
    case .split(let axis, let ratio, let pinned, let first, let second):
        "\(axis == .horizontal ? "H" : "V")\(ratio)\(pinned ? "!" : "")(\(shape(first)),\(shape(second)))"
    }
}

private func roundHalfUp(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

/// The space between every two frames that face each other with no other frame between them, across and
/// down. Frames that merely line up, or that have a third frame in the way, are not counted.
private func facingGaps(_ all: [TileRect]) -> [Double] {
    var gaps: [Double] = []
    for i in all.indices {
        for j in all.indices where j != i {
            let a = all[i], b = all[j]
            if b.minX >= a.maxX {
                let low = max(a.minY, b.minY), high = min(a.maxY, b.maxY)
                if high > low {
                    let blocked = all.indices.contains { k in
                        let c = all[k]
                        return k != i && k != j && c.minX < b.minX && c.maxX > a.maxX && min(c.maxY, high) > max(c.minY, low)
                    }
                    if !blocked { gaps.append(b.minX - a.maxX) }
                }
            }
            if b.minY >= a.maxY {
                let low = max(a.minX, b.minX), high = min(a.maxX, b.maxX)
                if high > low {
                    let blocked = all.indices.contains { k in
                        let c = all[k]
                        return k != i && k != j && c.minY < b.minY && c.maxY > a.maxY && min(c.maxX, high) > max(c.minX, low)
                    }
                    if !blocked { gaps.append(b.minY - a.maxY) }
                }
            }
        }
    }
    return gaps
}

private func contains(_ outer: TileRect, _ inner: TileRect) -> Bool {
    inner.minX >= outer.minX && inner.maxX <= outer.maxX && inner.minY >= outer.minY && inner.maxY <= outer.maxY
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
    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

private func randomNode(_ rng: inout SplitMix, counter: inout Int, depth: Int) -> TileNode {
    if depth == 0 || rng.int(4) == 0 {
        counter += 1
        return .leaf(window: id(counter))
    }
    let ratios: [Double] = [0, 0.15, 0.5, 0.85, 1, rng.unit(), rng.unit(), .nan, -3, 7, .infinity, -.infinity]
    let ratio = ratios[rng.int(ratios.count)]
    let axis: TileAxis = rng.int(2) == 0 ? .horizontal : .vertical
    let first = randomNode(&rng, counter: &counter, depth: depth - 1)
    let second = randomNode(&rng, counter: &counter, depth: depth - 1)
    return .split(axis: axis, ratio: ratio, pinned: rng.int(2) == 0, first: first, second: second)
}

@Suite struct TileEngineTests {
    // MARK: Tree basics

    @Test func anEmptyTreeIsDefined() {
        let tree = TileTree(displayID: 3)
        #expect(tree.displayID == 3)
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.windows.isEmpty)
        #expect(tree.order.isEmpty)
        #expect(!tree.contains(id(1)))
        #expect(frames(tree).isEmpty)
    }

    @Test func aTreeBuiltFromARootKeepsTreeOrderAsInsertionOrder() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.5, pinned: false,
                                  first: .leaf(window: id(7)),
                                  second: .split(axis: .vertical, ratio: 0.5, pinned: false,
                                                 first: .leaf(window: id(3)), second: .leaf(window: id(5))))
        let tree = TileTree(displayID: 2, root: root)
        #expect(tree.windows == [id(7), id(3), id(5)])
        #expect(tree.order == [id(7), id(3), id(5)])
        #expect(tree.count == 3)
        #expect(tree.depth == 2)
        #expect(root.depth(of: id(5)) == 2)
        #expect(root.depth(of: id(7)) == 1)
        #expect(root.depth(of: id(99)) == nil)
    }

    @Test func anOrderThatDisagreesWithTheRootIsRepaired() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.5, pinned: false,
                                  first: .leaf(window: id(1)), second: .leaf(window: id(2)))
        // Unknown id dropped, duplicate dropped, missing id appended in tree order.
        let tree = TileTree(displayID: 0, root: root, order: [id(9), id(2), id(2)])
        #expect(tree.order == [id(2), id(1)])
    }

    @Test func windowIdsOrderByPidThenIndex() {
        #expect(TileWindowID(pid: 1, index: 9) < TileWindowID(pid: 2, index: 0))
        #expect(TileWindowID(pid: 2, index: 0) < TileWindowID(pid: 2, index: 1))
        #expect(Set([id(1), id(1), id(2)]).count == 2)
    }

    // MARK: 1. Frame math

    @Test func oneToEightWindowsCoverThePaddedAreaWithoutOverlap() {
        let cfg = config()
        let usable = TileFrames.usableRect(display: wide, outerGap: cfg.outerGap)
        #expect(usable == TileRect(x: 16, y: 16, width: 1888, height: 1048))
        for count in 1...8 {
            let tree = build(count)
            let map = frames(tree)
            #expect(map.count == count)
            #expect(Set(map.keys) == Set((1...count).map(id)))
            let all = Array(map.values)
            // Every frame is a real tile inside the padded area and meets the minimum.
            for frame in all {
                #expect(!frame.isEmpty)
                #expect(frame.minX >= usable.minX && frame.maxX <= usable.maxX)
                #expect(frame.minY >= usable.minY && frame.maxY <= usable.maxY)
                #expect(frame.width >= cfg.minTileSize && frame.height >= cfg.minTileSize)
            }
            // The frames touch all four edges of the padded area.
            #expect(all.map(\.minX).min() == usable.minX)
            #expect(all.map(\.maxX).max() == usable.maxX)
            #expect(all.map(\.minY).min() == usable.minY)
            #expect(all.map(\.maxY).max() == usable.maxY)
            // No two frames overlap, and any two sit at least one inner gap apart along some axis.
            for i in all.indices {
                for j in all.indices where j > i {
                    #expect(!all[i].overlaps(all[j]))
                    let apart = max(all[i].minX - all[j].maxX, all[j].minX - all[i].maxX,
                                    all[i].minY - all[j].maxY, all[j].minY - all[i].maxY)
                    #expect(apart >= cfg.innerGap)
                }
            }
            // Frames that face each other with nothing between them sit exactly one inner gap apart.
            let gaps = facingGaps(all)
            #expect(gaps.isEmpty == (count == 1))
            #expect(gaps.allSatisfy { $0 == cfg.innerGap })
        }
    }

    @Test func withNoGapsTheFramesTileThePaddedAreaExactly() {
        let cfg = config(inner: 0, outer: 0)
        for count in 1...8 {
            let map = frames(build(count, config: cfg), config: cfg)
            let area = map.values.reduce(0) { $0 + $1.width * $1.height }
            #expect(area == wide.width * wide.height)
        }
    }

    @Test func theTwoThreeAndFourWindowShapesAreColumnsThenRows() {
        let one = frames(build(1))
        #expect(one[id(1)] == TileRect(x: 16, y: 16, width: 1888, height: 1048))

        // Two windows: a wide slot becomes two columns one inner gap apart.
        let two = frames(build(2))
        #expect(two[id(1)] == TileRect(x: 16, y: 16, width: 940, height: 1048))
        #expect(two[id(2)] == TileRect(x: 964, y: 16, width: 940, height: 1048))

        // Three: the newest slot is taller than it is wide, so it becomes two rows.
        let three = frames(build(3))
        #expect(three[id(1)] == two[id(1)])
        #expect(three[id(2)] == TileRect(x: 964, y: 16, width: 940, height: 520))
        #expect(three[id(3)] == TileRect(x: 964, y: 544, width: 940, height: 520))

        // Four: the newest slot is wide again, so it becomes two columns.
        let four = frames(build(4))
        #expect(four[id(1)] == two[id(1)])
        #expect(four[id(2)] == three[id(2)])
        #expect(four[id(3)] == TileRect(x: 964, y: 544, width: 466, height: 520))
        #expect(four[id(4)] == TileRect(x: 1438, y: 544, width: 466, height: 520))
    }

    @Test func aSplitHonoursItsRatioAndTheGapStaysOne() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.25, pinned: false,
                                  first: .leaf(window: id(1)), second: .leaf(window: id(2)))
        let map = TileFrames.frames(root, in: TileRect(x: 0, y: 0, width: 1008, height: 500), innerGap: 8)
        // (1008 - 8) * 0.25 = 250 for the first child; the second takes the rest after the gap.
        #expect(map[id(1)] == TileRect(x: 0, y: 0, width: 250, height: 500))
        #expect(map[id(2)] == TileRect(x: 258, y: 0, width: 750, height: 500))
    }

    @Test func oddSizesRoundEdgesSoSharedEdgesStayExact() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.5, pinned: false,
                                  first: .leaf(window: id(1)), second: .leaf(window: id(2)))
        let map = TileFrames.frames(root, in: TileRect(x: 0, y: 0, width: 101, height: 50), innerGap: 8)
        let a = map[id(1)]!, b = map[id(2)]!
        #expect(a.maxX + 8 == b.minX)
        #expect(a.minX == 0 && b.maxX == 101)
        #expect(a.width == a.width.rounded() && b.width == b.width.rounded())
        // A negative origin rounds the same way: translating by whole points never changes the sizes.
        let shifted = TileFrames.frames(root, in: TileRect(x: -300, y: -10, width: 101, height: 50), innerGap: 8)
        #expect(shifted[id(1)]?.width == a.width)
        #expect(shifted[id(2)]?.width == b.width)
        #expect(shifted[id(2)]!.minX - shifted[id(1)]!.maxX == 8)
    }

    @Test func aFractionalGapIsRoundedToWholePointsAndStaysExact() {
        let cfg = config(inner: 2.5, outer: 3.5)
        #expect(cfg.innerGap == 3 && cfg.outerGap == 4)
        for count in 1...8 {
            let all = Array(frames(build(count, config: cfg), config: cfg).values)
            for i in all.indices {
                for j in all.indices where j > i { #expect(!all[i].overlaps(all[j])) }
            }
            #expect(facingGaps(all).allSatisfy { $0 == 3 })
        }
        // The frame math rounds a fractional gap too, so a caller that skips the config still gets whole gaps.
        let root = build(4).root!
        let usable = TileRect(x: 16.25, y: 16.5, width: 1887.5, height: 1047.75)
        let direct = Array(TileFrames.frames(root, in: usable, innerGap: 2.5).values)
        #expect(facingGaps(direct).allSatisfy { $0 == 3 })
    }

    // MARK: 2. Determinism

    @Test func theSameIdsAndRectAlwaysGiveTheSameFrames() {
        let reference = frames(build(6))
        for _ in 0..<10 { #expect(frames(build(6)) == reference) }
        let root = build(6).root!
        let usable = TileFrames.usableRect(display: wide, outerGap: 16)
        #expect(TileFrames.frames(root, in: usable, innerGap: 8) == reference)
        #expect(TileTree(displayID: 1, root: root, order: build(6).order) == build(6))
    }

    // MARK: 3. Insert dwindles along the longer side

    @Test func theAxisFollowsTheLongerSide() {
        // A wide display: the first split is columns.
        guard case .inserted(let wideTree) = TileOps.insert(id(2), into: build(1), focused: nil, display: wide, config: config()) else {
            Issue.record("refused"); return
        }
        #expect(wideTree.root == .split(axis: .horizontal, ratio: 0.5, pinned: false,
                                        first: .leaf(window: id(1)), second: .leaf(window: id(2))))

        // A tall display: the first split is rows.
        let tall = TileRect(x: 0, y: 0, width: 800, height: 1400)
        let tallCfg = config(outer: 0)
        guard case .inserted(let tallTree) = TileOps.insert(id(2), into: build(1, display: tall, config: tallCfg), focused: nil,
                                                            display: tall, config: tallCfg) else {
            Issue.record("refused"); return
        }
        #expect(tallTree.root == .split(axis: .vertical, ratio: 0.5, pinned: false,
                                        first: .leaf(window: id(1)), second: .leaf(window: id(2))))

        // A square slot has no longer side: it becomes columns, always.
        let square = TileRect(x: 0, y: 0, width: 900, height: 900)
        guard case .inserted(let squareTree) = TileOps.insert(id(2), into: build(1, display: square, config: tallCfg), focused: nil,
                                                              display: square, config: tallCfg) else {
            Issue.record("refused"); return
        }
        #expect(shape(squareTree.root!) == "H0.5(L,L)")
    }

    @Test func aNewWindowSplitsTheNewestSlotAndTakesTheSecondSide() {
        let tree = build(4)
        #expect(shape(tree.root!) == "H0.5(L,V0.5(L,H0.5(L,L)))")
        #expect(tree.windows == [id(1), id(2), id(3), id(4)])
        #expect(tree.order == [id(1), id(2), id(3), id(4)])
    }

    @Test func aFocusedWindowSplitsItsOwnSlot() {
        let base = build(3)
        guard case .inserted(let tree) = TileOps.insert(id(4), into: base, focused: id(1), display: wide, config: config()) else {
            Issue.record("refused"); return
        }
        // Window 1 keeps the first side of its slot; the new window takes the second.
        #expect(tree.windows == [id(1), id(4), id(2), id(3)])
        #expect(tree.order == [id(1), id(2), id(3), id(4)])
        #expect(shape(tree.root!) == "H0.5(V0.5(L,L),V0.5(L,L))")
        // A focused id that is not in the tree falls back to the newest slot.
        guard case .inserted(let fallback) = TileOps.insert(id(4), into: base, focused: id(99), display: wide, config: config()) else {
            Issue.record("refused"); return
        }
        #expect(fallback == build(4))
    }

    @Test func theDefaultRatioIsUsedForANewSplit() {
        let cfg = config(ratio: 0.3)
        let tree = build(2, config: cfg)
        #expect(shape(tree.root!) == "H0.3(L,L)")
        let map = frames(tree, config: cfg)
        // (1888 - 8) * 0.3 = 564.
        #expect(map[id(1)]?.width == 564)
    }

    @Test func insertingAWindowThatIsAlreadyThereChangesNothing() {
        let tree = build(3)
        #expect(TileOps.insert(id(2), into: tree, focused: id(1), display: wide, config: config()) == .inserted(tree))
    }

    // MARK: 4. Depth and minimum size

    @Test func theDepthLimitRefusesTheNinthWindowAndKeepsEightTiles() {
        let tree = build(8)
        #expect(tree.depth == 3)
        #expect(tree.count == 8)
        #expect(TileOps.insert(id(9), into: tree, focused: nil, display: wide, config: config()) == .refused)
        #expect(TileOps.insert(id(9), into: tree, focused: id(5), display: wide, config: config()) == .refused)
    }

    @Test func aDepthOfOneAllowsTwoTilesOnly() {
        let cfg = config(maxDepth: 1)
        let tree = build(2, config: cfg)
        #expect(TileOps.insert(id(3), into: tree, focused: nil, display: wide, config: cfg) == .refused)
    }

    @Test func aWindowThatBreaksTheMinimumTriesTheOtherSlotsFromLastToFirst() {
        // 500 x 400 with no gaps and a 200 point minimum.
        let small = TileRect(x: 0, y: 0, width: 500, height: 400)
        let cfg = config(inner: 0, outer: 0, minTile: 200)
        let three = build(3, display: small, config: cfg)
        #expect(frames(three, display: small, config: cfg)[id(3)] == TileRect(x: 250, y: 200, width: 250, height: 200))
        // Window 4 cannot split window 3 or window 2 (both 250 x 200, so 125 wide), so it takes window 1's slot.
        guard case .inserted(let four) = TileOps.insert(id(4), into: three, focused: nil, display: small, config: cfg) else {
            Issue.record("refused"); return
        }
        #expect(four.windows == [id(1), id(4), id(2), id(3)])
        // Window 5 has nowhere to go: every slot is 250 x 200 now. The caller leaves it floating.
        #expect(TileOps.insert(id(5), into: four, focused: nil, display: small, config: cfg) == .refused)
    }

    @Test func aTileExactlyAtTheMinimumIsAccepted() {
        let small = TileRect(x: 0, y: 0, width: 400, height: 200)
        let cfg = config(inner: 0, outer: 0, minTile: 200)
        let one = build(1, display: small, config: cfg)
        #expect(TileOps.insert(id(2), into: one, focused: nil, display: small, config: cfg) != .refused)
        let tooNarrow = TileRect(x: 0, y: 0, width: 399, height: 200)
        let narrowOne = build(1, display: tooNarrow, config: cfg)
        #expect(TileOps.insert(id(2), into: narrowOne, focused: nil, display: tooNarrow, config: cfg) == .refused)
    }

    @Test func theInnerGapCountsTowardTheMinimum() {
        // Two 200 point columns need 408 points with an 8 point gap.
        let cfg = config(inner: 8, outer: 0, minTile: 200)
        let fits = TileRect(x: 0, y: 0, width: 408, height: 300)
        let notQuite = TileRect(x: 0, y: 0, width: 407, height: 300)
        #expect(TileOps.insert(id(2), into: build(1, display: fits, config: cfg), focused: nil, display: fits, config: cfg) != .refused)
        #expect(TileOps.insert(id(2), into: build(1, display: notQuite, config: cfg), focused: nil, display: notQuite, config: cfg) == .refused)
    }

    @Test func anEmptyTreeTakesTheFirstWindowEvenOnADegenerateDisplay() {
        let none = TileRect(x: 0, y: 0, width: 0, height: 0)
        guard case .inserted(let tree) = TileOps.insert(id(1), into: TileTree(displayID: 1), focused: nil, display: none, config: config()) else {
            Issue.record("refused"); return
        }
        #expect(tree.root == .leaf(window: id(1)))
        // The second window has no room, so it is refused.
        #expect(TileOps.insert(id(2), into: tree, focused: nil, display: none, config: config()) == .refused)
    }

    // MARK: 5. Remove

    @Test func removingAWindowPromotesItsSiblingAndKeepsTheOthersInPlace() {
        let tree = build(3)
        let before = frames(tree)
        // Window 3 leaves: window 2 takes the whole second column.
        let afterThree = TileOps.remove(id(3), from: tree)
        #expect(afterThree.root == .split(axis: .horizontal, ratio: 0.5, pinned: false,
                                          first: .leaf(window: id(1)), second: .leaf(window: id(2))))
        let mapThree = frames(afterThree)
        #expect(mapThree[id(1)] == before[id(1)])
        #expect(mapThree[id(2)] == TileRect(x: 964, y: 16, width: 940, height: 1048))
        #expect(afterThree.order == [id(1), id(2)])

        // Window 1 leaves: the stacked pair takes the whole area and keeps its own ratio.
        let afterOne = TileOps.remove(id(1), from: tree)
        #expect(shape(afterOne.root!) == "V0.5(L,L)")
        #expect(frames(afterOne)[id(2)] == TileRect(x: 16, y: 16, width: 1888, height: 520))
        #expect(frames(afterOne)[id(3)] == TileRect(x: 16, y: 544, width: 1888, height: 520))
    }

    @Test func removingFromTheFirstSideLeavesTheSecondSideFramesAlone() {
        // Window 1 and 2 are stacked on the left, window 3 is a column on the right.
        let root = TileNode.split(axis: .horizontal, ratio: 0.5, pinned: false,
                                  first: .split(axis: .vertical, ratio: 0.5, pinned: false,
                                                first: .leaf(window: id(1)), second: .leaf(window: id(2))),
                                  second: .leaf(window: id(3)))
        let tree = TileTree(displayID: 1, root: root)
        let before = frames(tree)
        let after = TileOps.remove(id(2), from: tree)
        #expect(shape(after.root!) == "H0.5(L,L)")
        let map = frames(after)
        #expect(map[id(3)] == before[id(3)])
        #expect(map[id(1)] == TileRect(x: 16, y: 16, width: 940, height: 1048))
    }

    @Test func removalCollapsesOnlyOneLevelAndKeepsEveryOtherRatio() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.7, pinned: true,
                                  first: .leaf(window: id(1)),
                                  second: .split(axis: .vertical, ratio: 0.3, pinned: false,
                                                 first: .leaf(window: id(2)),
                                                 second: .split(axis: .horizontal, ratio: 0.6, pinned: true,
                                                                first: .leaf(window: id(3)), second: .leaf(window: id(4)))))
        let tree = TileTree(displayID: 1, root: root)
        let after = TileOps.remove(id(2), from: tree)
        #expect(shape(after.root!) == "H0.7!(L,H0.6!(L,L))")
        #expect(after.windows == [id(1), id(3), id(4)])
    }

    @Test func removingTheOnlyWindowEmptiesTheTree() {
        let tree = TileOps.remove(id(1), from: build(1))
        #expect(tree.isEmpty)
        #expect(tree.root == nil)
        #expect(tree.displayID == 1)
    }

    // MARK: 6. Swap

    @Test func swapExchangesTwoSlotsAndLeavesTheShapeAlone() {
        let tree = build(4)
        let before = frames(tree)
        let swapped = TileOps.swap(id(1), id(4), in: tree)
        #expect(shape(swapped.root!) == shape(tree.root!))
        // The order follows the slots, so the newest slot is still the same place after a swap.
        #expect(swapped.order == [id(4), id(2), id(3), id(1)])
        let after = frames(swapped)
        #expect(after[id(1)] == before[id(4)])
        #expect(after[id(4)] == before[id(1)])
        #expect(after[id(2)] == before[id(2)])
        #expect(after[id(3)] == before[id(3)])
        // Swapping back restores the original, and the argument order does not matter.
        #expect(TileOps.swap(id(4), id(1), in: swapped) == tree)
    }

    @Test func theNewestSlotStaysPutAfterASwapSoTilesKeepDwindling() {
        let tree = build(3)
        let before = frames(tree)
        let swapped = TileOps.swap(id(1), id(3), in: tree)
        // Window 1 now holds the newest slot, the lower right one.
        #expect(frames(swapped)[id(1)] == before[id(3)])
        guard case .inserted(let grown) = TileOps.insert(id(5), into: swapped, focused: nil, display: wide, config: config()) else {
            Issue.record("window 5 was refused")
            return
        }
        // With nothing focused the next window splits that same slot, not the left column.
        let after = frames(grown)
        let slot = before[id(3)]!
        #expect(contains(slot, after[id(1)]!))
        #expect(contains(slot, after[id(5)]!))
        #expect(after[id(3)] == before[id(1)])
        #expect(after[id(2)] == before[id(2)])
    }

    @Test func swapKeepsEveryRatioAndPin() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.7, pinned: true,
                                  first: .leaf(window: id(1)),
                                  second: .split(axis: .vertical, ratio: 0.3, pinned: false,
                                                 first: .leaf(window: id(2)), second: .leaf(window: id(3))))
        let tree = TileTree(displayID: 1, root: root)
        let swapped = TileOps.swap(id(2), id(1), in: tree)
        #expect(shape(swapped.root!) == shape(root))
        #expect(swapped.windows == [id(2), id(1), id(3)])
        // The tree was given without an order, so it started as tree order and the swap trades the two slots.
        #expect(swapped.order == [id(2), id(1), id(3)])
    }

    // MARK: 7. Flip

    @Test func flipTurnsColumnsIntoRowsAndPinsTheSplit() {
        let tree = build(2)
        let flipped = TileOps.flip(at: id(2), in: tree)
        #expect(flipped.root == .split(axis: .vertical, ratio: 0.5, pinned: true,
                                       first: .leaf(window: id(1)), second: .leaf(window: id(2))))
        let map = frames(flipped)
        #expect(map[id(1)] == TileRect(x: 16, y: 16, width: 1888, height: 520))
        #expect(map[id(2)] == TileRect(x: 16, y: 544, width: 1888, height: 520))
        // A second flip goes back to columns and the pin stays on.
        let back = TileOps.flip(at: id(1), in: flipped)
        #expect(shape(back.root!) == "H0.5!(L,L)")
    }

    @Test func aPinnedAxisSurvivesALaterInsert() {
        let flipped = TileOps.flip(at: id(2), in: build(2))
        guard case .inserted(let tree) = TileOps.insert(id(3), into: flipped, focused: id(2), display: wide, config: config()) else {
            Issue.record("refused"); return
        }
        guard case .split(let axis, _, let pinned, _, _) = tree.root! else {
            Issue.record("the root is not a split"); return
        }
        #expect(axis == .vertical)
        #expect(pinned)
        #expect(tree.count == 3)
    }

    @Test func flipOnlyTouchesTheParentOfTheFocusedWindow() {
        let tree = build(3)
        let flipped = TileOps.flip(at: id(3), in: tree)
        #expect(shape(flipped.root!) == "H0.5(L,H0.5!(L,L))")
    }

    // MARK: 8. Ratio clamp and nudge

    @Test func theRatioClampsToItsBounds() {
        #expect(TileRatio.minimum == 0.15)
        #expect(TileRatio.maximum == 0.85)
        #expect(TileRatio.standard == 0.5)
        #expect(TileRatio.clamp(0.1) == 0.15)
        #expect(TileRatio.clamp(0.9) == 0.85)
        #expect(TileRatio.clamp(0.4) == 0.4)
        #expect(TileRatio.clamp(0.15) == 0.15)
        #expect(TileRatio.clamp(0.85) == 0.85)
        #expect(TileRatio.clamp(-2) == 0.15)
        #expect(TileRatio.clamp(.infinity) == 0.85)
        #expect(TileRatio.clamp(-.infinity) == 0.15)
        #expect(TileRatio.clamp(.nan) == 0.5)
    }

    @Test func nudgeMovesTheNearestSplitOnTheMatchingSide() {
        // Window 1 on the left, windows 2 over 3 on the right.
        let tree = build(3)
        // Window 1 is on the first side of the columns: right grows it.
        let right = TileOps.nudgeRatio(at: id(1), direction: .right, step: 0.05, in: tree)
        #expect(shape(right.root!) == "H0.55(L,V0.5(L,L))")
        #expect(frames(right)[id(1)]?.width == 1034)
        // Window 2 is on the first side of the rows: down grows it, and the columns stay put.
        let down = TileOps.nudgeRatio(at: id(2), direction: .down, step: 0.05, in: tree)
        #expect(shape(down.root!) == "H0.5(L,V0.55(L,L))")
        // Window 2 is on the second side of the columns: left grows it by moving the columns' split.
        let left = TileOps.nudgeRatio(at: id(2), direction: .left, step: 0.05, in: tree)
        #expect(shape(left.root!) == "H0.45(L,V0.5(L,L))")
        // Window 3 is on the second side of the rows: up grows it.
        let up = TileOps.nudgeRatio(at: id(3), direction: .up, step: 0.05, in: tree)
        #expect(shape(up.root!) == "H0.5(L,V0.45(L,L))")
    }

    @Test func nudgeDoesNothingWhenNoSplitMatchesTheDirectionAndSide() {
        let tree = build(3)
        #expect(TileOps.nudgeRatio(at: id(1), direction: .left, step: 0.05, in: tree) == tree)
        #expect(TileOps.nudgeRatio(at: id(1), direction: .down, step: 0.05, in: tree) == tree)
        #expect(TileOps.nudgeRatio(at: id(2), direction: .right, step: 0.05, in: tree) == tree)
        #expect(TileOps.nudgeRatio(at: id(3), direction: .down, step: 0.05, in: tree) == tree)
        #expect(TileOps.nudgeRatio(at: id(99), direction: .right, step: 0.05, in: tree) == tree)
    }

    @Test func nudgeKeepsLookingUpTheTreeForAMatchingAncestor() {
        let root = TileNode.split(axis: .horizontal, ratio: 0.5, pinned: false,
                                  first: .split(axis: .horizontal, ratio: 0.5, pinned: false,
                                                first: .leaf(window: id(1)), second: .leaf(window: id(2))),
                                  second: .leaf(window: id(3)))
        let tree = TileTree(displayID: 1, root: root)
        // Window 1 is on the first side of the inner split, which is the nearest match.
        #expect(shape(TileOps.nudgeRatio(at: id(1), direction: .right, step: 0.05, in: tree).root!) == "H0.5(H0.55(L,L),L)")
        // Window 2 is on the second side of the inner split, so the outer split is the nearest match.
        #expect(shape(TileOps.nudgeRatio(at: id(2), direction: .right, step: 0.05, in: tree).root!) == "H0.55(H0.5(L,L),L)")
        // Window 3 is on the second side of the outer split only.
        #expect(shape(TileOps.nudgeRatio(at: id(3), direction: .left, step: 0.05, in: tree).root!) == "H0.45(H0.5(L,L),L)")
    }

    @Test func nudgeClampsAndDoesNotPassTheLimitToAFartherSplit() {
        let tree = build(2)
        let max = TileOps.nudgeRatio(at: id(1), direction: .right, step: 1, in: tree)
        #expect(shape(max.root!) == "H0.85(L,L)")
        #expect(TileOps.nudgeRatio(at: id(1), direction: .right, step: 0.05, in: max) == max)
        let min = TileOps.nudgeRatio(at: id(2), direction: .left, step: 1, in: tree)
        #expect(shape(min.root!) == "H0.15(L,L)")

        // The nearest match is already at its limit: the farther split is left alone.
        let root = TileNode.split(axis: .horizontal, ratio: 0.5, pinned: false,
                                  first: .split(axis: .horizontal, ratio: 0.85, pinned: false,
                                                first: .leaf(window: id(1)), second: .leaf(window: id(2))),
                                  second: .leaf(window: id(3)))
        let nested = TileTree(displayID: 1, root: root)
        #expect(TileOps.nudgeRatio(at: id(1), direction: .right, step: 0.05, in: nested) == nested)
    }

    @Test func nudgeIgnoresAStepThatIsNotANumber() {
        let tree = build(2)
        #expect(TileOps.nudgeRatio(at: id(1), direction: .right, step: .nan, in: tree) == tree)
    }

    // MARK: 9. Focus by direction

    private let a = id(1), b = id(2), c = id(3)

    @Test func theLargestCrossAxisOverlapWinsBeforeDistance() {
        let map: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 120, y: 0, width: 100, height: 30), // overlap 30, edge distance 20
            c: TileRect(x: 140, y: 20, width: 100, height: 70), // overlap 70, edge distance 40
        ]
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map) == c)
    }

    @Test func equalOverlapFallsBackToTheNearestEdge() {
        let map: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 110, y: 0, width: 100, height: 50), // overlap 50, distance 10
            c: TileRect(x: 130, y: 50, width: 100, height: 50), // overlap 50, distance 30
        ]
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map) == b)
    }

    @Test func equalOverlapAndDistanceFallBackToRecencyThenToTheLowestId() {
        let map: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 110, y: 0, width: 100, height: 50),
            c: TileRect(x: 110, y: 50, width: 100, height: 50),
        ]
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map, recency: [c, b]) == c)
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map, recency: [b, c]) == b)
        // A window missing from the recency list ranks after the ones in it.
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map, recency: [c]) == c)
        // No recency at all: the lowest id, so the answer never depends on dictionary order.
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map) == b)
    }

    @Test func nothingThatWayGivesNil() {
        let map: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 110, y: 0, width: 100, height: 100),
        ]
        #expect(TileOps.neighbour(of: a, direction: .left, frames: map) == nil)
        #expect(TileOps.neighbour(of: a, direction: .up, frames: map) == nil)
        #expect(TileOps.neighbour(of: a, direction: .down, frames: map) == nil)
        #expect(TileOps.neighbour(of: b, direction: .right, frames: map) == nil)
        #expect(TileOps.neighbour(of: c, direction: .right, frames: map) == nil)
        #expect(TileOps.neighbour(of: a, direction: .right, frames: [:]) == nil)
        #expect(TileOps.neighbour(of: a, direction: .right, frames: [a: map[a]!]) == nil)
    }

    @Test func aWindowThatOverlapsTheEdgeIsNotBeyondIt() {
        let map: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 50, y: 0, width: 100, height: 100),
        ]
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map) == nil)
        // Touching edges count as beyond.
        let touching: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 100, y: 0, width: 100, height: 100),
        ]
        #expect(TileOps.neighbour(of: a, direction: .right, frames: touching) == b)
    }

    @Test func aWindowWithAnEmptyFrameIsNeverChosen() {
        let map: [TileWindowID: TileRect] = [
            a: TileRect(x: 0, y: 0, width: 100, height: 100),
            b: TileRect(x: 110, y: 0, width: 0, height: 0),
        ]
        #expect(TileOps.neighbour(of: a, direction: .right, frames: map) == nil)
    }

    @Test func focusMovesAcrossARealLayoutInEveryDirection() {
        let map = frames(build(4))
        // Window 1 fills the left column; windows 2, 3 and 4 tie on overlap and 2 and 3 tie on distance.
        #expect(TileOps.neighbour(of: id(1), direction: .right, frames: map) == id(2))
        #expect(TileOps.neighbour(of: id(1), direction: .right, frames: map, recency: [id(3)]) == id(3))
        #expect(TileOps.neighbour(of: id(4), direction: .left, frames: map) == id(3))
        #expect(TileOps.neighbour(of: id(3), direction: .up, frames: map) == id(2))
        #expect(TileOps.neighbour(of: id(2), direction: .down, frames: map) == id(3))
        #expect(TileOps.neighbour(of: id(3), direction: .left, frames: map) == id(1))
        #expect(TileOps.neighbour(of: id(2), direction: .left, frames: map) == id(1))
        #expect(TileOps.neighbour(of: id(1), direction: .left, frames: map) == nil)
        #expect(TileOps.neighbour(of: id(1), direction: .up, frames: map) == nil)
        #expect(TileOps.neighbour(of: id(4), direction: .right, frames: map) == nil)
        #expect(TileOps.neighbour(of: id(4), direction: .down, frames: map) == nil)
    }

    @Test func focusWorksOverTheUnionOfTwoDisplays() {
        let left = TileRect(x: 0, y: 0, width: 1920, height: 1080)
        let right = TileRect(x: 1920, y: 0, width: 1920, height: 1080)
        let cfg = config()
        let first = build(2, display: left, config: cfg)
        var second = TileTree(displayID: 2)
        for n in 11...12 {
            guard case .inserted(let next) = TileOps.insert(id(n), into: second, focused: nil, display: right, config: cfg) else {
                Issue.record("refused"); return
            }
            second = next
        }
        let union = frames(first, display: left, config: cfg).merging(frames(second, display: right, config: cfg)) { x, _ in x }
        #expect(union.count == 4)
        // The right column of the left display looks right into the left column of the right display.
        #expect(TileOps.neighbour(of: id(2), direction: .right, frames: union) == id(11))
        #expect(TileOps.neighbour(of: id(11), direction: .left, frames: union) == id(2))
        #expect(TileOps.neighbour(of: id(12), direction: .right, frames: union) == nil)
    }

    // MARK: 10. Reconcile

    @Test func reconcileInsertsNewWindowsInDiscoveryOrder() {
        let result = TileOps.reconcile(tree: TileTree(displayID: 1), eligible: [id(1), id(2), id(3)],
                                       order: [id(3), id(1), id(2)], display: wide, config: config())
        #expect(result.refused.isEmpty)
        #expect(result.tree.order == [id(3), id(1), id(2)])
        #expect(result.tree.windows == [id(3), id(1), id(2)])
        #expect(result.tree.displayID == 1)
    }

    @Test func reconcileRemovesGoneWindowsAndKeepsTheRest() {
        let tree = build(3)
        let before = frames(tree)
        let result = TileOps.reconcile(tree: tree, eligible: [id(1), id(3)], order: [id(1), id(2), id(3)],
                                       display: wide, config: config())
        #expect(result.refused.isEmpty)
        #expect(result.tree == TileOps.remove(id(2), from: tree))
        #expect(frames(result.tree)[id(1)] == before[id(1)])
        // Nothing changes when nothing changed.
        let same = TileOps.reconcile(tree: tree, eligible: [id(1), id(2), id(3)], order: [id(3), id(2), id(1)],
                                     display: wide, config: config())
        #expect(same.tree == tree)
        #expect(same.refused.isEmpty)
    }

    @Test func reconcileAddsOnlyTheNewWindowsAfterTheExistingOnes() {
        let tree = build(2)
        let result = TileOps.reconcile(tree: tree, eligible: [id(1), id(2), id(4), id(5)],
                                       order: [id(1), id(2), id(5), id(4)], display: wide, config: config())
        #expect(result.tree.order == [id(1), id(2), id(5), id(4)])
        #expect(result.tree.windows.prefix(2) == [id(1), id(2)])
        #expect(result.refused.isEmpty)
    }

    @Test func reconcileReportsTheWindowsItCouldNotFit() {
        let small = TileRect(x: 0, y: 0, width: 500, height: 400)
        let cfg = config(inner: 0, outer: 0, minTile: 200)
        let eligible = Set((1...6).map(id))
        let result = TileOps.reconcile(tree: TileTree(displayID: 1), eligible: eligible, order: (1...6).map(id),
                                       display: small, config: cfg)
        #expect(result.tree.count == 4)
        #expect(result.refused == [id(5), id(6)])
        #expect(!result.tree.contains(id(5)))
    }

    @Test func reconcileTreatsFloatingWindowsAsNotTiled() {
        let tree = build(3)
        let cfg = config(floating: [id(2), id(9)])
        let result = TileOps.reconcile(tree: tree, eligible: [id(1), id(2), id(3), id(9)],
                                       order: [id(1), id(2), id(3), id(9)], display: wide, config: cfg)
        #expect(result.tree.windows == [id(1), id(3)])
        #expect(result.refused.isEmpty)
    }

    @Test func reconcileIsDefinedForOddInputs() {
        // Ids in the order list that are not eligible are ignored; duplicates are inserted once;
        // eligible ids missing from the order list are added last, lowest id first.
        let result = TileOps.reconcile(tree: TileTree(displayID: 1), eligible: [id(2), id(4), id(3)],
                                       order: [id(9), id(3), id(3), id(2)], display: wide, config: config())
        #expect(result.tree.order == [id(3), id(2), id(4)])
        #expect(result.refused.isEmpty)
        // Nothing eligible empties the tree.
        let emptied = TileOps.reconcile(tree: build(3), eligible: [], order: [], display: wide, config: config())
        #expect(emptied.tree.isEmpty)
        #expect(emptied.refused.isEmpty)
    }

    // MARK: Operations on empty, single and unknown inputs

    @Test func everyOperationIsDefinedOnEmptySingleAndUnknownInputs() {
        let empty = TileTree(displayID: 4)
        let single = build(1)
        #expect(TileOps.remove(id(1), from: empty) == empty)
        #expect(TileOps.swap(id(1), id(2), in: empty) == empty)
        #expect(TileOps.flip(at: id(1), in: empty) == empty)
        #expect(TileOps.nudgeRatio(at: id(1), direction: .left, step: 0.05, in: empty) == empty)

        #expect(TileOps.remove(id(9), from: single) == single)
        #expect(TileOps.swap(id(1), id(1), in: single) == single)
        #expect(TileOps.swap(id(1), id(9), in: single) == single)
        #expect(TileOps.flip(at: id(1), in: single) == single)
        #expect(TileOps.flip(at: id(9), in: single) == single)
        #expect(TileOps.nudgeRatio(at: id(1), direction: .right, step: 0.05, in: single) == single)

        let two = build(2)
        #expect(TileOps.swap(id(1), id(9), in: two) == two)
        #expect(TileOps.swap(id(2), id(2), in: two) == two)
        #expect(TileOps.flip(at: id(9), in: two) == two)
        #expect(TileOps.remove(id(9), from: two) == two)
    }

    // MARK: Degenerate rectangles

    @Test func aDegenerateDisplayGivesEveryWindowAnEmptyFrameInsideIt() {
        let tree = build(5)
        let rects = [
            TileRect(x: 0, y: 0, width: 0, height: 0),
            TileRect(x: 10, y: 10, width: -50, height: 200),
            TileRect(x: 5, y: 5, width: 20, height: 20), // smaller than the outer gap on both sides
            TileRect(x: .nan, y: 0, width: 100, height: 100),
            TileRect(x: 0, y: 0, width: .infinity, height: 100),
        ]
        for rect in rects {
            let map = frames(tree, display: rect)
            #expect(map.count == 5)
            for frame in map.values {
                #expect(frame.isEmpty)
                #expect(frame.width >= 0 && frame.height >= 0)
                #expect(frame.x.isFinite && frame.y.isFinite)
            }
        }
    }

    @Test func theUsableRectNeverInverts() {
        #expect(TileFrames.usableRect(display: TileRect(x: 0, y: 0, width: 1000, height: 500), outerGap: 10)
            == TileRect(x: 10, y: 10, width: 980, height: 480))
        #expect(TileFrames.usableRect(display: TileRect(x: 0, y: 0, width: 1000, height: 500), outerGap: 0)
            == TileRect(x: 0, y: 0, width: 1000, height: 500))
        // A gap larger than half the display collapses to a point on the centre line.
        #expect(TileFrames.usableRect(display: TileRect(x: 0, y: 0, width: 100, height: 50), outerGap: 60)
            == TileRect(x: 50, y: 25, width: 0, height: 0))
        // A gap that only eats one dimension keeps the other.
        #expect(TileFrames.usableRect(display: TileRect(x: 0, y: 0, width: 100, height: 400), outerGap: 60)
            == TileRect(x: 50, y: 60, width: 0, height: 280))
        // A negative or unreadable gap counts as none.
        #expect(TileFrames.usableRect(display: TileRect(x: 1, y: 2, width: 30, height: 40), outerGap: -5)
            == TileRect(x: 1, y: 2, width: 30, height: 40))
        #expect(TileFrames.usableRect(display: TileRect(x: 1, y: 2, width: 30, height: 40), outerGap: .nan)
            == TileRect(x: 1, y: 2, width: 30, height: 40))
        // A display that is not a rectangle becomes an empty one.
        #expect(TileFrames.usableRect(display: TileRect(x: 1, y: 2, width: -30, height: 40), outerGap: 4).isEmpty)
        #expect(TileFrames.usableRect(display: TileRect(x: .nan, y: 2, width: 30, height: 40), outerGap: 4).isEmpty)
    }

    @Test func theRectValueHelpersAgree() {
        let r = TileRect(x: 10, y: 20, width: 30, height: 40)
        #expect(r.minX == 10 && r.maxX == 40 && r.minY == 20 && r.maxY == 60)
        #expect(r.midX == 25 && r.midY == 40)
        #expect(!r.isEmpty)
        #expect(TileRect(x: 0, y: 0, width: 0, height: 5).isEmpty)
        #expect(TileRect(x: 0, y: 0, width: 5, height: -1).isEmpty)
        #expect(TileRect(x: 0, y: 0, width: .nan, height: 5).isEmpty)
        #expect(r.inset(by: 5) == TileRect(x: 15, y: 25, width: 20, height: 30))
        #expect(r.overlaps(TileRect(x: 39, y: 59, width: 10, height: 10)))
        #expect(!r.overlaps(TileRect(x: 40, y: 20, width: 10, height: 10)))
        #expect(!r.overlaps(TileRect(x: 10, y: 60, width: 10, height: 10)))
        #expect(!TileRect(x: 0, y: 0, width: 0, height: 0).overlaps(r))
    }

    @Test func aTinyRectWithBigGapsAndExtremeRatiosNeverInverts() {
        let root = TileNode.split(axis: .horizontal, ratio: 0, pinned: false,
                                  first: .leaf(window: id(1)),
                                  second: .split(axis: .vertical, ratio: 1, pinned: false,
                                                 first: .leaf(window: id(2)), second: .leaf(window: id(3))))
        let map = TileFrames.frames(root, in: TileRect(x: 0, y: 0, width: 5, height: 5), innerGap: 64)
        #expect(map.count == 3)
        for frame in map.values { #expect(frame.width >= 0 && frame.height >= 0) }
        // A ratio of 0 is clamped to the minimum, not allowed to hide the first window outright.
        let normal = TileFrames.frames(root, in: TileRect(x: 0, y: 0, width: 1000, height: 1000), innerGap: 0)
        #expect(normal[id(1)]?.width == 150)
    }

    // MARK: Any tree and any rect

    @Test func anyTreeInAnyRectGivesNonOverlappingFramesInsideThePaddedArea() {
        var rng = SplitMix(state: 20_261_114)
        let sizes: [Double] = [0, 1, 7, 33, 101, 250, 640, 1440.5, 1920, 5120]
        for _ in 0..<400 {
            var counter = 0
            let node = randomNode(&rng, counter: &counter, depth: 1 + rng.int(5))
            let display = TileRect(x: Double(rng.int(4000)) - 2000 + (rng.int(2) == 0 ? 0.5 : 0),
                                   y: Double(rng.int(4000)) - 2000,
                                   width: sizes[rng.int(sizes.count)] + (rng.int(3) == 0 ? 0.25 : 0),
                                   height: sizes[rng.int(sizes.count)])
            let cfg = TileConfig(innerGap: Double(rng.int(80)) - 8, outerGap: Double(rng.int(80)) - 8)
            let tree = TileTree(displayID: 1, root: node)
            let map = TileFrames.frames(of: tree, display: display, config: cfg)
            let usable = TileFrames.usableRect(display: display, outerGap: cfg.outerGap)
            #expect(map.count == tree.count)
            let left = roundHalfUp(usable.minX), right = roundHalfUp(usable.maxX)
            let top = roundHalfUp(usable.minY), bottom = roundHalfUp(usable.maxY)
            let all = Array(map.values)
            for frame in all {
                #expect(frame.width >= 0 && frame.height >= 0)
                #expect(frame.minX >= left && frame.maxX <= right)
                #expect(frame.minY >= top && frame.maxY <= bottom)
                #expect(frame.x == frame.x.rounded() && frame.width == frame.width.rounded())
            }
            for i in all.indices {
                for j in all.indices where j > i { #expect(!all[i].overlaps(all[j])) }
            }
            // The same input again gives the same answer.
            #expect(TileFrames.frames(of: tree, display: display, config: cfg) == map)
        }
    }

    @Test func randomInsertsAndRemovesKeepTheTreeConsistentAndFramesDisjoint() {
        var rng = SplitMix(state: 99)
        let cfg = config(inner: 6, outer: 10, maxDepth: 4, minTile: 120)
        var tree = TileTree(displayID: 1)
        var next = 0
        for _ in 0..<300 {
            if tree.isEmpty || rng.int(3) != 0 {
                next += 1
                let focused = tree.windows.isEmpty || rng.int(2) == 0 ? nil : tree.windows[rng.int(tree.windows.count)]
                if case .inserted(let grown) = TileOps.insert(id(next), into: tree, focused: focused, display: wide, config: cfg) {
                    tree = grown
                }
            } else {
                tree = TileOps.remove(tree.windows[rng.int(tree.windows.count)], from: tree)
            }
            #expect(Set(tree.order) == Set(tree.windows))
            #expect(tree.order.count == tree.windows.count)
            #expect(tree.depth <= cfg.maxDepth)
            let map = frames(tree, config: cfg)
            #expect(map.count == tree.count)
            let all = Array(map.values)
            // Inserts only add tiles that meet the minimum, and a removal only makes the survivors bigger.
            for frame in all { #expect(frame.width >= cfg.minTileSize && frame.height >= cfg.minTileSize) }
            for i in all.indices {
                for j in all.indices where j > i { #expect(!all[i].overlaps(all[j])) }
            }
        }
    }

    // MARK: 12. Config

    @Test func theConfigDefaultsMatchThePlan() {
        let cfg = TileConfig()
        #expect(!cfg.enabled)
        #expect(!cfg.paused)
        #expect(cfg.innerGap == 8)
        #expect(cfg.outerGap == 8)
        #expect(cfg.maxDepth == 3)
        #expect(cfg.minTileSize == 200)
        #expect(cfg.defaultRatio == 0.5)
        #expect(cfg.base == .controlOptionCommand)
        #expect(cfg.floating.isEmpty)
        #expect(cfg.excludedBundleIDs.isEmpty)
        #expect(TileConfig.defaults == cfg)
    }

    @Test func theConfigRoundsGapsToWholePoints() {
        let cfg = TileConfig(innerGap: 2.4, outerGap: 7.6)
        #expect(cfg.innerGap == 2 && cfg.outerGap == 8)
        #expect(TileConfig(innerGap: 63.6, outerGap: 0.4).innerGap == 64)
        #expect(TileConfig(innerGap: 63.6, outerGap: 0.4).outerGap == 0)
        #expect(TileConfig(innerGap: 64.4).innerGap == 64)
    }

    @Test func theConfigClampsEveryNumber() {
        let low = TileConfig(innerGap: -5, outerGap: -1, maxDepth: 0, minTileSize: 10, defaultRatio: 0.05)
        #expect(low.innerGap == 0 && low.outerGap == 0)
        #expect(low.maxDepth == 1)
        #expect(low.minTileSize == 120)
        #expect(low.defaultRatio == 0.15)
        let high = TileConfig(innerGap: 100, outerGap: 65, maxDepth: 9, minTileSize: 1000, defaultRatio: 0.99)
        #expect(high.innerGap == 64 && high.outerGap == 64)
        #expect(high.maxDepth == 4)
        #expect(high.minTileSize == 600)
        #expect(high.defaultRatio == 0.85)
        let inside = TileConfig(innerGap: 0, outerGap: 64, maxDepth: 4, minTileSize: 120, defaultRatio: 0.3)
        #expect(inside.innerGap == 0 && inside.outerGap == 64 && inside.maxDepth == 4)
        #expect(inside.minTileSize == 120 && inside.defaultRatio == 0.3)
    }

    @Test func unreadableConfigNumbersFallBackToTheDefaults() {
        let cfg = TileConfig(innerGap: .nan, outerGap: .nan, minTileSize: .nan, defaultRatio: .nan)
        #expect(cfg.innerGap == 8 && cfg.outerGap == 8)
        #expect(cfg.minTileSize == 200)
        #expect(cfg.defaultRatio == 0.5)
        let infinite = TileConfig(innerGap: .infinity, outerGap: -.infinity, minTileSize: .infinity, defaultRatio: .infinity)
        #expect(infinite.innerGap == 64 && infinite.outerGap == 0)
        #expect(infinite.minTileSize == 600 && infinite.defaultRatio == 0.85)
    }

    @Test func theConfigCarriesItsSetsAndFlags() {
        let cfg = TileConfig(enabled: true, paused: true, base: .optionCommand, floating: [id(1)], excludedBundleIDs: ["com.example.app"])
        #expect(cfg.enabled && cfg.paused)
        #expect(cfg.base == .optionCommand)
        #expect(cfg.floating == [id(1)])
        #expect(cfg.excludedBundleIDs == ["com.example.app"])
    }
}
