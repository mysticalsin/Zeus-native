import Foundation
import Testing
@testable import ZeusCore

@Suite("Desktop explanation card: placement, fallback ladder, lifecycle and content fitting")
struct ExplanationCardPlacementTests {
    private typealias Placement = ExplanationCardPlacement
    private let roomy = ExplanationRect(x: 0, y: 0, width: 1440, height: 875)

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ExplanationRect {
        ExplanationRect(x: x, y: y, width: width, height: height)
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    /// 400 x 300 diagram, 80 characters of caption: a 460 x 435 card at full size.
    private var typical: ExplanationCardContent {
        ExplanationCardContent(visual: .init(width: 400, height: 300), hasWorld: false, captionCharacters: 80)
    }

    private func request(_ usable: ExplanationRect, anchor: ExplanationRect?, protected: [ExplanationRect] = [],
                         reserved: [ExplanationRect] = [], content: ExplanationCardContent? = nil,
                         beat: ExplanationCardContent? = nil) -> ExplanationCardRequest {
        ExplanationCardRequest(usable: usable, anchor: anchor, protected: protected, reserved: reserved,
                               content: content ?? typical, beat: beat)
    }

    /// The card never covers a protected region (with its margin) and stays inside the usable area.
    private func isClear(_ layout: ExplanationCardLayout, usable: ExplanationRect, protected: [ExplanationRect],
                         reserved: [ExplanationRect] = []) -> Bool {
        guard let frame = layout.frame else { return false }
        let inside = frame.x >= usable.x && frame.y >= usable.y
            && frame.x + frame.width <= usable.x + usable.width && frame.y + frame.height <= usable.y + usable.height
        let clear = !protected.contains { Placement.intersects(Placement.inflate($0, by: Placement.protectedMargin), frame) }
        let free = !reserved.contains { Placement.intersects($0, frame) }
        return inside && clear && free
    }

    // MARK: protected regions

    @Test func cardPlacementPrefersTheRightOfTheSubjectWithAShortConnector() throws {
        let subject = rect(700, 400, 100, 40)
        let layout = Placement.place(request(roomy, anchor: subject, protected: [subject]))
        let frame = try #require(layout.frame)
        #expect(layout.rung == .preferred && layout.tier == .full)
        #expect(near(frame.x, 820) && near(frame.width, 460) && near(frame.y, 420 - frame.height / 2))
        let connector = try #require(layout.connector)
        #expect(near(connector.from.x, 820) && near(connector.to.x, 800) && near(connector.to.y, 420))
        #expect(isClear(layout, usable: roomy, protected: [subject]))
    }

    @Test func cardPlacementNeverCoversTheTargetThePointerTrailOrTheInputArea() {
        let subject = rect(700, 400, 100, 40)
        let trail = rect(600, 380, 300, 80)
        let input = rect(800, 300, 600, 300)
        for protected in [[subject], [subject, trail], [subject, input], [subject, trail, input]] {
            let layout = Placement.place(request(roomy, anchor: subject, protected: protected))
            #expect(layout.rung != .speechOnly)
            #expect(isClear(layout, usable: roomy, protected: protected))
        }
    }

    @Test func cardPlacementMovesToTheLeftWhenTheInputAreaTakesTheRight() throws {
        let subject = rect(700, 400, 100, 40)
        let input = rect(800, 300, 600, 300)
        let layout = Placement.place(request(roomy, anchor: subject, protected: [subject, input]))
        let frame = try #require(layout.frame)
        #expect(layout.rung == .preferred)
        #expect(frame.x + frame.width <= 680 + 0.001)
    }

    @Test func cardPlacementAvoidsReservedMenuBarAndDockBands() throws {
        let dock = rect(0, 0, 1440, 80)
        let subject = rect(700, 100, 100, 40)
        let layout = Placement.place(request(roomy, anchor: subject, protected: [subject], reserved: [dock]))
        let frame = try #require(layout.frame)
        #expect(frame.y >= 80)
        #expect(isClear(layout, usable: roomy, protected: [subject], reserved: [dock]))
    }

    @Test func cardPlacementShiftsAwayFromAScreenEdge() throws {
        let subject = rect(1380, 400, 40, 40)
        let layout = Placement.place(request(roomy, anchor: subject, protected: [subject]))
        let frame = try #require(layout.frame)
        #expect(layout.rung == .preferred)
        #expect(frame.x + frame.width <= 1360 + 0.001)
        #expect(isClear(layout, usable: roomy, protected: [subject]))
    }

    // MARK: displays

    @Test func cardPlacementWorksOnADisplayWithANegativeOrigin() throws {
        let left = rect(-1920, 0, 1920, 1055)
        let subject = rect(-1000, 500, 80, 30)
        let layout = Placement.place(request(left, anchor: subject, protected: [subject]))
        let frame = try #require(layout.frame)
        #expect(near(frame.x, -900), "subject right edge -920 plus the 20 pt connector gap")
        #expect(frame.x < 0 && frame.x + frame.width < 0)
        #expect(isClear(layout, usable: left, protected: [subject]))
        let below = rect(1440, -900, 1920, 1055)
        let target = rect(1800, -300, 60, 30)
        let other = Placement.place(request(below, anchor: target, protected: [target]))
        #expect(other.rung != .speechOnly)
        #expect(isClear(other, usable: below, protected: [target]))
    }

    @Test func cardPlacementOnTheOtherDisplayIsIndependentOfThisOne() throws {
        let main = rect(0, 0, 1440, 875)
        let side = rect(1440, 0, 1920, 1055)
        let subject = rect(1600, 500, 80, 30)
        let onSide = Placement.place(request(side, anchor: subject, protected: [subject]))
        let frame = try #require(onSide.frame)
        #expect(frame.x >= side.x)
        #expect(!Placement.intersects(frame, main))
    }

    // MARK: fallback ladder

    private var blockedAllAround: [ExplanationRect] {
        [rect(340, 200, 100, 400), rect(560, 200, 100, 400), rect(270, 470, 460, 60), rect(270, 290, 460, 60)]
    }

    @Test func cardLadderMovesElsewhereAtFullSizeWhenEveryHuggingSpotIsTaken() throws {
        let usable = rect(0, 0, 1000, 800)
        let subject = rect(480, 380, 40, 40)
        let small = ExplanationCardContent(visual: nil, hasWorld: false, captionCharacters: 20)
        let protected = [subject] + blockedAllAround
        let layout = Placement.place(request(usable, anchor: subject, protected: protected, content: small))
        let frame = try #require(layout.frame)
        #expect(layout.rung == .moved && layout.tier == .full)
        #expect(isClear(layout, usable: usable, protected: protected))
        #expect(Placement.distance(frame, subject) <= Placement.maxConnectorDistance)
        #expect(layout.connector != nil)
    }

    @Test func cardLadderShrinksAndDropsNonessentialWorldContentWhenFullDoesNotFit() throws {
        let short = rect(0, 0, 1440, 474)
        let subject = rect(700, 200, 100, 40)
        let busy = ExplanationCardContent(visual: .init(width: 500, height: 300), hasWorld: true, captionCharacters: 20)
        let layout = Placement.place(request(short, anchor: subject, protected: [subject], content: busy))
        #expect(layout.rung == .shrunk && layout.tier == .compact)
        #expect(layout.showsWorld == false)
        #expect(layout.visualScale >= Placement.minimumVisualScale)
        #expect(isClear(layout, usable: short, protected: [subject]))
    }

    @Test func cardLadderSplitsIntoBeatsWhenTheWholeSceneIsTooLargeToReadSmall() throws {
        let subject = rect(700, 400, 100, 40)
        let whole = ExplanationCardContent(visual: .init(width: 1500, height: 900), hasWorld: false, captionCharacters: 40)
        let beat = ExplanationCardContent(visual: .init(width: 400, height: 250), hasWorld: false, captionCharacters: 40)
        let layout = Placement.place(request(roomy, anchor: subject, protected: [subject], content: whole, beat: beat))
        #expect(layout.rung == .split && layout.beatOnly)
        #expect(layout.visualScale >= Placement.minimumVisualScale)
        #expect(isClear(layout, usable: roomy, protected: [subject]))
    }

    @Test func cardLadderEndsInSpeechOnlyWithNoFrameAndNoConnector() {
        let subject = rect(700, 400, 100, 40)
        let huge = ExplanationCardContent(visual: .init(width: 3000, height: 2000), hasWorld: false, captionCharacters: 40)
        let noBeat = Placement.place(request(roomy, anchor: subject, protected: [subject], content: huge))
        #expect(noBeat.rung == .speechOnly && noBeat.frame == nil && noBeat.connector == nil)
        let sameBeat = Placement.place(request(roomy, anchor: subject, protected: [subject], content: huge, beat: huge))
        #expect(sameBeat.rung == .speechOnly)
        let tiny = rect(0, 0, 300, 200)
        let cramped = Placement.place(request(tiny, anchor: rect(100, 80, 40, 30), protected: [], content: typical))
        #expect(cramped.rung == .speechOnly && cramped.frame == nil)
    }

    @Test func cardLadderNeverPlacesADiagramBelowTheReadableScale() {
        let subject = rect(700, 400, 100, 40)
        for width in stride(from: 100.0, through: 2500.0, by: 100.0) {
            for height in [150.0, 400.0, 900.0] {
                let content = ExplanationCardContent(visual: .init(width: width, height: height), hasWorld: false, captionCharacters: 60)
                let layout = Placement.place(request(roomy, anchor: subject, protected: [subject], content: content))
                #expect(layout.rung == .speechOnly || layout.visualScale >= Placement.minimumVisualScale)
                if layout.frame != nil { #expect(layout.visualScale <= Placement.maximumVisualScale) }
            }
        }
    }

    @Test func cardConnectorStaysShortWheneverACardIsShown() throws {
        let subject = rect(700, 400, 100, 40)
        let layouts = [
            Placement.place(request(roomy, anchor: subject, protected: [subject])),
            Placement.place(request(rect(0, 0, 1000, 800), anchor: rect(480, 380, 40, 40),
                                    protected: [rect(480, 380, 40, 40)] + blockedAllAround,
                                    content: ExplanationCardContent(visual: nil, hasWorld: false, captionCharacters: 20))),
        ]
        for layout in layouts {
            let connector = try #require(layout.connector)
            let length = hypot(connector.to.x - connector.from.x, connector.to.y - connector.from.y)
            #expect(length <= Placement.maxConnectorDistance + 0.001)
        }
    }

    @Test func cardCaptionIsNeverClippedSoAnOverlongOneMeansSpeechOnly() {
        let subject = rect(700, 400, 100, 40)
        let long = ExplanationCardContent(visual: .init(width: 300, height: 200), hasWorld: false, captionCharacters: 1_000)
        let refused = Placement.place(request(roomy, anchor: subject, protected: [subject], content: long))
        #expect(refused.rung == .speechOnly)
        let fits = ExplanationCardContent(visual: .init(width: 300, height: 200), hasWorld: false, captionCharacters: 500)
        let shown = Placement.place(request(roomy, anchor: subject, protected: [subject], content: fits))
        #expect(shown.rung != .speechOnly)
        #expect(shown.captionHeight >= 10 * 18)
    }

    @Test func cardLayoutReportsTheSectionSizesTheViewMustUse() throws {
        let subject = rect(700, 400, 100, 40)
        let layout = Placement.place(request(roomy, anchor: subject, protected: [subject]))
        let frame = try #require(layout.frame)
        let visual = try #require(layout.visualSize)
        #expect(near(visual.width, 400 * layout.visualScale) && near(visual.height, 300 * layout.visualScale))
        #expect(near(frame.height, 32 + 12 + 8 + visual.height + 8 + layout.captionHeight))
        #expect(layout.worldHeight == 0)
    }

    @Test func cardWithNoSubjectGoesToACornerWithoutAConnector() throws {
        let layout = Placement.place(request(roomy, anchor: nil))
        let frame = try #require(layout.frame)
        #expect(layout.connector == nil)
        #expect(near(frame.x + frame.width, 1428) && near(frame.y + frame.height, 863))
    }

    // MARK: lifecycle

    @Test func cardLifecycleRejectsALateCallbackFromAReplacedTurn() {
        var lifecycle = ExplanationCardLifecycle()
        let first = UUID(), second = UUID()
        #expect(!lifecycle.admits(first))
        lifecycle.begin(token: first)
        #expect(lifecycle.admits(first))
        lifecycle.begin(token: second)
        #expect(!lifecycle.admits(first))
        #expect(lifecycle.admits(second))
        lifecycle.end()
        #expect(!lifecycle.admits(second))
    }

    @Test func cardLifecycleStaysClosedAfterTheOwnerClosesUntilTheNextTurn() {
        var lifecycle = ExplanationCardLifecycle()
        let turn = UUID(), next = UUID()
        lifecycle.begin(token: turn)
        lifecycle.dismissByOwner()
        #expect(!lifecycle.admits(turn))
        lifecycle.begin(token: next)
        #expect(lifecycle.admits(next))
    }

    // MARK: content

    private func object(_ id: String, _ kind: ExplanationGeometry.Kind, x: Double = 0, y: Double = 0,
                        size: (Double, Double)? = nil, parent: String? = nil, text: String? = nil,
                        from: String? = nil, to: String? = nil) -> ExplanationObject {
        ExplanationObject(id: id, parentID: parent, space: .canvas,
                          geometry: .init(kind: kind, size: size.map { .init(x: $0.0, y: $0.1) }, fromID: from, toID: to),
                          transform: .init(position: .init(x: x, y: y)), text: text, accessibleDescription: "d")
    }

    private func scene(_ objects: [ExplanationObject]) -> ExplanationScene {
        ExplanationScene(sessionID: UUID(), sceneID: UUID(), objects: Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) }))
    }

    @Test func cardContentKeepsOnlyNonCaptureObjectsAndTheirDependencies() throws {
        let capture = UUID()
        let ring = ExplanationObject(id: "ring", space: .capture, captureID: capture,
                                     geometry: .init(kind: .ring, radius: 20), accessibleDescription: "d")
        var full = scene([object("a", .roundedRectangle, size: (50, 50)), object("g", .group),
                          object("c", .roundedRectangle, size: (50, 50), parent: "g"),
                          object("k", .connector, from: "a", to: "c"), ring])
        full.captureID = capture
        let card = try #require(ExplanationCardContentBuilder.cardScene(from: full))
        #expect(Set(card.objects.keys) == ["a", "g", "c", "k"])
        #expect(card.captureID == nil)
        let focused = try #require(ExplanationCardContentBuilder.cardScene(from: full, focus: ["k"]))
        #expect(Set(focused.objects.keys) == ["a", "g", "c", "k"])
        let only = try #require(ExplanationCardContentBuilder.cardScene(from: full, focus: ["a"]))
        #expect(Set(only.objects.keys) == ["a"])
        var marksOnly = scene([])
        marksOnly.objects["ring"] = ring
        #expect(ExplanationCardContentBuilder.cardScene(from: marksOnly) == nil)
    }

    @Test func cardContentFitsTheDiagramBoundsNotTheWholeStage() throws {
        let source = scene([object("r", .roundedRectangle, x: 500, y: 300, size: (200, 100))])
        let fit = ExplanationCardContentBuilder.fit(source)
        #expect(fit.hasCanvas && !fit.hasWorld)
        #expect(near(fit.dx, 472) && near(fit.dy, 272))
        #expect(near(fit.canvasSize.width, 256) && near(fit.canvasSize.height, 156))
        let shifted = ExplanationCardContentBuilder.applying(fit, to: source)
        let moved = try #require(shifted.objects["r"])
        #expect(near(moved.transform.position.x, 28))
        #expect(shifted.canvasSize == fit.canvasSize)
        try ExplanationSceneReducer.validate(shifted)
    }

    @Test func cardContentLeavesRoomForLabelsAndShiftsOnlyRootsOfAGroup() throws {
        let labelled = scene([object("r", .roundedRectangle, x: 500, y: 300, size: (200, 100), text: "Hi")])
        #expect(near(ExplanationCardContentBuilder.fit(labelled).canvasSize.width, 456))
        let grouped = scene([object("g", .group, x: 100, y: 100), object("c", .roundedRectangle, x: 10, y: 10, size: (50, 50), parent: "g")])
        let fit = ExplanationCardContentBuilder.fit(grouped)
        #expect(near(fit.dx, 82))
        let shifted = ExplanationCardContentBuilder.applying(fit, to: grouped)
        let group = try #require(shifted.objects["g"])
        let child = try #require(shifted.objects["c"])
        #expect(near(group.transform.position.x, 18))
        #expect(near(child.transform.position.x, 10))
        try ExplanationSceneReducer.validate(shifted)
    }

    @Test func cardContentReportsWorldAndCaptionSizeForPlacement() {
        let box = ExplanationObject(id: "b", space: .world, geometry: .init(kind: .box, size: .init(x: 1, y: 1, z: 1)),
                                    accessibleDescription: "d")
        let mixed = scene([box, object("r", .roundedRectangle, size: (100, 100))])
        let fit = ExplanationCardContentBuilder.fit(mixed)
        let content = ExplanationCardContentBuilder.content(fit, caption: "Hello there")
        #expect(content.hasWorld && content.visual != nil && content.captionCharacters == 11)
        let worldOnly = ExplanationCardContentBuilder.fit(scene([box]))
        #expect(worldOnly.hasWorld && !worldOnly.hasCanvas)
        #expect(ExplanationCardContentBuilder.content(worldOnly, caption: "").visual == nil)
    }
}
