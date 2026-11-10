import Foundation
import Testing
@testable import ZeusCore

@Suite("Bot avatars")
struct BotAvatarSpecTests {
    // MARK: Shapes

    @Test func everyTypeIsAClosedPathInsideTheBox() {
        for type in BotAvatarType.allCases {
            let spec = BotAvatarSpec.spec(for: type)
            #expect(spec.outline.isClosed, "\(type) is not closed")
            #expect(spec.outline.fits(inBox: 100), "\(type) leaves the box")
            #expect(spec.bounds.width > 40 && spec.bounds.height > 30, "\(type) is too small")
            #expect(spec.bounds.contains(spec.faceAnchor), "\(type) face anchor is outside the body box")
            #expect(spec.bounds.contains(BotPoint(spec.faceAnchor.x - spec.eyeSpacing, spec.faceAnchor.y)), "\(type) left eye")
            #expect(spec.bounds.contains(BotPoint(spec.faceAnchor.x + spec.eyeSpacing, spec.faceAnchor.y)), "\(type) right eye")
        }
        #expect(BotAvatarType.allCases.count == 18)
    }

    @Test func coloursAreDistinct() {
        let hexes = BotAvatarType.allCases.map { BotAvatarSpec.spec(for: $0).defaultColorHex }
        #expect(Set(hexes).count == hexes.count)
    }

    @Test func shapesAreDistinct() {
        let outlines = BotAvatarType.allCases.map { BotAvatarSpec.spec(for: $0).outline.commands.count }
        #expect(outlines.allSatisfy { $0 > 8 })
        for (i, a) in BotAvatarType.allCases.enumerated() {
            for b in BotAvatarType.allCases.dropFirst(i + 1) {
                #expect(BotAvatarSpec.spec(for: a).outline != BotAvatarSpec.spec(for: b).outline, "\(a) equals \(b)")
            }
        }
    }

    @Test func customPathReplacesTheOutline() throws {
        let custom = try #require(BotPath.parse("M20 20 L80 20 L50 80 Z"))
        let spec = BotAvatarSpec(type: .circle, customPath: custom)
        #expect(spec.outline == custom)
        #expect(spec.bounds == BotBounds(minX: 20, minY: 20, maxX: 80, maxY: 80))
    }

    // MARK: Parser

    @Test func parserReadsLinesCurvesAndClose() throws {
        let path = try #require(BotPath.parse("M10 10 L90 10 L50 90 Z"))
        #expect(path.commands == [.move(BotPoint(10, 10)), .line(BotPoint(90, 10)), .line(BotPoint(50, 90)), .close])

        let curved = try #require(BotPath.parse("M 10,10 C 20 0 80 0 90 10 Q 50 60 10 10 Z"))
        #expect(curved.commands == [
            .move(BotPoint(10, 10)),
            .cubic(control1: BotPoint(20, 0), control2: BotPoint(80, 0), to: BotPoint(90, 10)),
            .quad(control: BotPoint(50, 60), to: BotPoint(10, 10)),
            .close
        ])
        #expect(curved.isClosed)
    }

    @Test func parserHandlesImplicitRepeatsAndNumberForms() throws {
        let repeated = try #require(BotPath.parse("M0 0 L10 0 10 10 Z"))
        #expect(repeated.commands.count == 4)
        #expect(repeated.commands[2] == .line(BotPoint(10, 10)))

        let implicitLine = try #require(BotPath.parse("M0 0 5 5"))
        #expect(implicitLine.commands == [.move(BotPoint(0, 0)), .line(BotPoint(5, 5))])

        let forms = try #require(BotPath.parse("M-5.5 .5L1e1 2Z"))
        #expect(forms.commands == [.move(BotPoint(-5.5, 0.5)), .line(BotPoint(10, 2)), .close])

        let tight = try #require(BotPath.parse("M10-5L1.5.5Z"))
        #expect(tight.commands == [.move(BotPoint(10, -5)), .line(BotPoint(1.5, 0.5)), .close])
    }

    @Test func parserRejectsBadInput() {
        #expect(BotPath.parse("") == nil)
        #expect(BotPath.parse("X1 2") == nil)
        #expect(BotPath.parse("L 1 2") == nil)
        #expect(BotPath.parse("M 1") == nil)
        #expect(BotPath.parse("M 1 2 L 3") == nil)
        #expect(BotPath.parse("M 1 2 Q 3 4 5") == nil)
        #expect(BotPath.parse("M 1 2 Z 5 5") == nil)
        #expect(BotPath.parse("M 1 2 A 3 4 0 0 1 5 6") == nil)
    }

    // MARK: Timeline

    @Test func jumpCurveIsBoundedAndZeroAtBothEnds() {
        for ease in BotEase.allCases {
            #expect(BotTimeline.arc(0, ease: ease) == 0)
            #expect(BotTimeline.arc(1, ease: ease) == 0)
            #expect(BotTimeline.arc(-0.5, ease: ease) == 0)
            #expect(BotTimeline.arc(1.5, ease: ease) == 0)
            var peak = 0.0
            for i in 0...1000 {
                let v = BotTimeline.arc(Double(i) / 1000, ease: ease)
                #expect(v >= 0 && v <= 1.0000001, "\(ease) out of range at \(i)")
                peak = max(peak, v)
            }
            #expect(peak > 0.9, "\(ease) never gets high")
        }
    }

    @Test func jumpCurveIsContinuous() {
        for ease in BotEase.allCases {
            var previous = BotTimeline.arc(0, ease: ease)
            for i in 1...2000 {
                let v = BotTimeline.arc(Double(i) / 2000, ease: ease)
                #expect(abs(v - previous) < 0.05, "\(ease) jumps at step \(i)")
                previous = v
            }
        }
    }

    @Test func squashAndStretchJoinTheRestPose() {
        for jump in [BotJump.idle, .working, .click] {
            let start = BotTimeline.squashStretch(progress: 0, jump: jump)
            let end = BotTimeline.squashStretch(progress: 1, jump: jump)
            #expect(start.x == 1 && start.y == 1)
            #expect(end.x == 1 && end.y == 1)
            let nearStart = BotTimeline.squashStretch(progress: 0.0001, jump: jump)
            let nearEnd = BotTimeline.squashStretch(progress: 0.9999, jump: jump)
            #expect(abs(nearStart.y - 1) < 0.01 && abs(nearEnd.y - 1) < 0.01)
            let air = BotTimeline.squashStretch(progress: 0.5, jump: jump)
            #expect(air.y > 1 && air.x < 1)
            let landing = BotTimeline.squashStretch(progress: 0.91, jump: jump)
            #expect(landing.y < 1 && landing.x > 1)
        }
    }

    @Test func blinkIsBoundedAndSeededApart() {
        var sawBlink = false
        for seed in [0.0, 0.2, 0.37, 0.8] {
            for i in 0..<1200 {
                let v = BotTimeline.blink(time: Double(i) * 0.01, seed: seed)
                #expect(v >= 0 && v <= 1)
                if v > 0.9 { sawBlink = true }
            }
        }
        #expect(sawBlink)
        // Seed 0 starts a blink at t = 0; seed 0.37 is mid-interval then.
        #expect(BotTimeline.blink(time: 0.05, seed: 0) > 0.5)
        #expect(BotTimeline.blink(time: 0.05, seed: 0.37) == 0)
    }

    @Test func stateTimelinesStayBounded() {
        for state in BotAvatarState.allCases {
            for seed in [0.0, 0.3, 0.99] {
                for i in 0..<1500 {
                    let p = BotTimeline.pose(state: state, time: Double(i) * 0.033, seed: seed)
                    #expect(p.lift >= 0 && p.lift <= 0.25, "\(state) lift \(p.lift)")
                    #expect(p.sink >= 0 && p.sink <= 0.1)
                    #expect(p.scaleX > 0.6 && p.scaleX < 1.7)
                    #expect(p.scaleY > 0.6 && p.scaleY < 1.5)
                    #expect(p.rotation > -0.5 && p.rotation < 2 * Double.pi + 0.5)
                    #expect(abs(p.lookX) <= 1 && abs(p.lookY) <= 1)
                    #expect(p.lid >= 0 && p.lid <= 1)
                    #expect(p.squint >= 0 && p.squint <= 1)
                    #expect(p.mouthOpen >= 0 && p.mouthOpen <= 1)
                    #expect(p.breath > 0.9 && p.breath < 1.1)
                }
            }
        }
    }

    @Test func idleJumpsAboutEveryEightSeconds() {
        #expect(BotTimeline.pose(state: .default, time: 0.35, seed: 0).lift > 0.05)
        #expect(BotTimeline.pose(state: .default, time: 8.35, seed: 0).lift > 0.05)
        #expect(BotTimeline.pose(state: .default, time: 4, seed: 0).lift == 0)
        // Continuous across the start and end of a jump.
        let before = BotTimeline.pose(state: .default, time: 7.9999, seed: 0)
        let after = BotTimeline.pose(state: .default, time: 8.0001, seed: 0)
        #expect(abs(before.lift - after.lift) < 0.005 && abs(before.scaleY - after.scaleY) < 0.01)
        let landed = BotTimeline.pose(state: .default, time: 8.6999, seed: 0)
        let rested = BotTimeline.pose(state: .default, time: 8.7001, seed: 0)
        #expect(abs(landed.lift - rested.lift) < 0.005 && abs(landed.scaleY - rested.scaleY) < 0.01)
    }

    @Test func workingHopsSpinsAndLaughs() {
        var lifted = false, spun = false, openMouth = false
        for i in 0..<400 {
            let p = BotTimeline.pose(state: .working, time: Double(i) * 0.02)
            if p.lift > 0.05 { lifted = true }
            if p.rotation > 1 { spun = true }
            if p.mouthOpen > 0.8 { openMouth = true }
            #expect(p.squint > 0.5)
        }
        #expect(lifted && spun && openMouth)
    }

    @Test func sleepingHasHeadDownAndShutLids() {
        for i in 0..<300 {
            let p = BotTimeline.pose(state: .sleeping, time: Double(i) * 0.1, seed: 0.4)
            #expect(p.lid == 1)
            #expect(p.sink > 0)
            #expect(p.lift == 0)
            #expect(p.rotation > 0.1)
        }
        let breaths = (0..<100).map { BotTimeline.pose(state: .sleeping, time: Double($0) * 0.1).breath }
        #expect((breaths.max() ?? 1) - (breaths.min() ?? 1) > 0.04)
    }

    @Test func reduceMotionGivesAStillPose() {
        for state in BotAvatarState.allCases {
            let first = BotTimeline.pose(state: state, time: 0, seed: 0.2, reduceMotion: true)
            for t in [0.35, 1.7, 8.4, 123.4] {
                #expect(BotTimeline.pose(state: state, time: t, seed: 0.2, reduceMotion: true) == first)
            }
            #expect(first.lift == 0 && first.scaleX == 1 && first.scaleY == 1 && first.breath == 1)
        }
        #expect(BotTimeline.pose(state: .sleeping, time: 1, reduceMotion: true).lid == 1)
        #expect(BotTimeline.pose(state: .default, time: 1, reduceMotion: true).lid == 0)
    }

    @Test func clickHopsAndSpinsOnce() {
        let base = BotTimeline.pose(state: .default, time: 3)
        #expect(BotTimeline.clickPose(elapsed: -0.1, over: base) == nil)
        #expect(BotTimeline.clickPose(elapsed: BotJump.click.duration, over: base) == nil)
        let mid = BotTimeline.clickPose(elapsed: BotJump.click.duration * 0.5, over: base)
        #expect((mid?.lift ?? 0) > 0.05)
        let late = BotTimeline.clickPose(elapsed: BotJump.click.duration * 0.999, over: base)
        #expect(abs((late?.rotation ?? 0) - 2 * Double.pi) < 0.05)
        #expect(BotTimeline.clickPose(elapsed: 0.0001, over: base)?.lookX == base.lookX)
    }

    // MARK: Agents

    @Test func agentShapesAreStable() {
        for name in ["claude", "Codex", "gemini", "ZEUS", "a"] {
            #expect(BotAvatarSpec.type(forAgent: name) == BotAvatarSpec.type(forAgent: name))
            #expect(BotAvatarSpec.seed(forAgent: name) == BotAvatarSpec.seed(forAgent: name))
        }
        #expect(BotAvatarSpec.type(forAgent: "Claude") == BotAvatarSpec.type(forAgent: "  claude "))
        for name in ["claude", "codex", "zeus", ""] {
            let seed = BotAvatarSpec.seed(forAgent: name)
            #expect(seed >= 0 && seed < 1)
        }
    }

    @Test func agentShapesSpreadAcrossTheRoster() {
        var counts: [BotAvatarType: Int] = [:]
        for i in 0..<400 {
            counts[BotAvatarSpec.type(forAgent: "agent-\(i)"), default: 0] += 1
        }
        #expect(counts.count == BotAvatarType.allCases.count)
        #expect((counts.values.max() ?? 0) < 60)
        let seeds = Set((0..<100).map { BotAvatarSpec.seed(forAgent: "agent-\($0)") })
        #expect(seeds.count > 90)
    }

    // MARK: Shading, light, state helpers

    @Test func shadingStylesDiffer() {
        for shading in BotShading.allCases {
            let p = BotShadingParams.params(for: shading)
            for v in [p.contrast, p.gloss, p.rim] { #expect(v >= 0 && v <= 1) }
            #expect(p.rimWidth >= 0 && p.fuzz >= 0)
        }
        let flat = BotShadingParams.params(for: .flat)
        #expect(flat.contrast == 0 && flat.gloss == 0 && flat.rim == 0 && flat.fuzz == 0)
        #expect(BotShadingParams.params(for: .plastic).gloss > 0.3)
        #expect(BotShadingParams.params(for: .plush).fuzz > 0)
        #expect(BotShadingParams.params(for: .crisp).rim > BotShadingParams.params(for: .plastic).rim)
        #expect(BotShadingParams.params(for: .smooth).gloss == 0)
    }

    @Test func lightDirectionIsAUnitVectorPointingUpLeft() {
        for degrees in stride(from: -180.0, through: 180, by: 15) {
            let d = BotLight.direction(degrees: degrees)
            #expect(abs(d.x * d.x + d.y * d.y - 1) < 1e-9)
        }
        let d = BotLight.direction(degrees: BotLight.defaultAngleDegrees)
        #expect(d.x < 0 && d.y < 0)
    }

    @Test func colourMixing() {
        let c = BotRGB(hex: 0xFF8000)
        #expect(abs(c.r - 1) < 1e-9 && abs(c.b) < 1e-9)
        #expect(c.mixed(with: .white, 0) == c)
        #expect(c.mixed(with: .white, 1) == .white)
        #expect(c.mixed(with: .black, 7) == .black)
    }

    @Test func stateFollowsTheSession() {
        #expect(BotAvatarState.forActivity(running: true, idleFor: 0) == .working)
        #expect(BotAvatarState.forActivity(running: true, idleFor: 9999) == .working)
        #expect(BotAvatarState.forActivity(running: false, idleFor: 30) == .default)
        #expect(BotAvatarState.forActivity(running: false, idleFor: 600) == .sleeping)
        #expect(BotAvatarState.forActivity(running: false, idleFor: 100, sleepAfter: 60) == .sleeping)
    }

    @Test func accessibilityLabels() {
        #expect(BotAvatarSpec.accessibilityLabel(agent: "Ada", state: .working) == "Ada avatar, working")
        #expect(BotAvatarSpec.accessibilityLabel(agent: "Ada", state: .sleeping) == "Ada avatar, sleeping")
        #expect(BotAvatarSpec.accessibilityLabel(agent: "Ada", state: .default) == "Ada avatar, idle")
        #expect(BotAvatarSpec.accessibilityLabel(agent: nil, state: .default) == "Agent avatar, idle")
    }
}
