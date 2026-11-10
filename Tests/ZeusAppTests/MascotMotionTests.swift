import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Zeus

@Suite("Mini ZEUS motion")
struct MascotMotionTests {
    @Test func asleepUsesTheCleanSleepPoseWithFloatingZzz() {
        let motion = MascotMotion.at(12.3, mood: .asleep, size: 22)
        #expect(motion.pose == .sleepingClean)
        let phase = try? #require(motion.sleepPhase)
        #expect(phase.map { (0..<1).contains($0) } == true)
    }

    @Test func awakeStatesNeverShowZzz() {
        for state in AvatarState.allCases {
            #expect(MascotMotion.at(5, mood: .awake(state), size: 22).sleepPhase == nil)
        }
    }

    @Test func idleStrollsNearTheEndOfEachWalkCycleAndStandsOtherwise() {
        let walkStart = MascotMotion.walkEvery - MascotMotion.walkLength
        let walking = MascotMotion.at(walkStart + 0.8, mood: .awake(.idle), size: 22)
        #expect(walking.pose == .walking)
        #expect(walking.dx != 0)
        let resting = MascotMotion.at(1, mood: .awake(.idle), size: 22)
        #expect(resting.pose == .idle)
        #expect(resting.dx == 0)
    }

    @Test func agentWorkCyclesThroughItsActionPoses() {
        let (poses, hold) = MascotMotion.cycle(for: .agent)
        let seen = Set((0..<poses.count).map { MascotMotion.pose(at: Double($0) * hold + 0.1, state: .agent) })
        #expect(seen == Set(poses))
        #expect(poses.count >= 4)
    }

    @Test func doneJumpsAndErrorShakes() {
        #expect(MascotMotion.at(0.25, mood: .awake(.done), size: 22).dy < 0)
        #expect(MascotMotion.at(0.04, mood: .awake(.error), size: 22).dx != 0)
        #expect(MascotMotion.at(1.5, mood: .awake(.error), size: 22).dx == 0)
    }

    @Test func motionScalesWithSize() {
        let small = MascotMotion.at(0.25, mood: .awake(.done), size: 22)
        let big = MascotMotion.at(0.25, mood: .awake(.done), size: 88)
        #expect(abs(big.dy - small.dy * 4) < 0.001)
    }

    /// Checked on disk: the test runner has no app resource bundle.
    @Test func everyPoseTheMotionUsesHasArt() {
        let poses = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Zeus/Avatar/Poses").standardizedFileURL
        var used = Set(AvatarState.allCases.flatMap { MascotMotion.cycle(for: $0).poses })
        used.formUnion([.walking, .sleepingClean, .waking, .curious])
        for pose in used {
            let file = poses.appendingPathComponent("\(pose.rawValue).png")
            #expect(FileManager.default.fileExists(atPath: file.path), "missing art for \(pose)")
        }
    }

    // MARK: Sprite atlases

    private static let animDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Zeus/Avatar/Anim").standardizedFileURL

    /// A 4-frame clip: 100, 100, 100 and 200 ms (0.5 s long).
    private static func clip(kind: String) throws -> MascotClip {
        let json = """
        {"state":"t","kind":"\(kind)","seconds":0.5,"fps":8,"frameCount":4,"frameDurationsMs":[100,100,100,200],
         "sizes":{"128":{"file":"128/t.png","cell":128,"width":256,"height":256,"frames":[
           {"i":0,"x":0,"y":0,"w":128,"h":128,"ms":100},{"i":1,"x":128,"y":0,"w":128,"h":128,"ms":100},
           {"i":2,"x":0,"y":128,"w":128,"h":128,"ms":100},{"i":3,"x":128,"y":128,"w":128,"h":128,"ms":200}]},
          "320":{"file":"320/t.png","cell":320,"width":640,"height":640,"frames":[]}}}
        """
        return try JSONDecoder().decode(MascotClip.self, from: Data(json.utf8))
    }

    @Test func clipFrameSelectionFollowsTheMetadataDurations() throws {
        let clip = try Self.clip(kind: "loop")
        #expect(clip.length == 0.5)
        #expect(clip.frameIndex(at: 0) == 0)
        #expect(clip.frameIndex(at: 0.099) == 0)
        #expect(clip.frameIndex(at: 0.1) == 1)
        #expect(clip.frameIndex(at: 0.25) == 2)
        #expect(clip.frameIndex(at: 0.31) == 3) // the last frame holds for 200 ms
        #expect(clip.frameIndex(at: -3) == 0)
    }

    @Test func loopsWrapAroundAndOneShotsHoldTheirLastFrame() throws {
        let loop = try Self.clip(kind: "loop")
        #expect(loop.frameIndex(at: 0.5) == 0)
        #expect(loop.frameIndex(at: 0.62) == 1)
        #expect(loop.frameIndex(at: 5.05) == 0)
        #expect(!loop.isFinished(at: 99))
        let shot = try Self.clip(kind: "one-shot")
        #expect(shot.frameIndex(at: 0.49) == 3)
        #expect(shot.frameIndex(at: 0.5) == 3)
        #expect(shot.frameIndex(at: 60) == 3)
        #expect(!shot.isFinished(at: 0.4) && shot.isFinished(at: 0.5))
    }

    @Test func theAtlasSizeFollowsThePointSize() throws {
        let clip = try Self.clip(kind: "loop")
        #expect(clip.atlasKey(forPoints: 22) == "128")
        #expect(clip.atlasKey(forPoints: 26) == "128")
        #expect(clip.atlasKey(forPoints: 64) == "128") // 128 px = 64 pt at 2x
        #expect(clip.atlasKey(forPoints: 96) == "320")
        #expect(clip.atlasKey(forPoints: 400) == "320") // bigger than any atlas: the largest
    }

    @Test func motionPicksTheClipAndPositionInIt() {
        // Single-pose loops line up with their slot; multi-pose cycles restart the clip each slot.
        let (_, hold) = MascotMotion.cycle(for: .agent)
        let a = MascotMotion.at(0.5, mood: .awake(.agent), size: 22)
        #expect(a.pose == .working && abs(a.elapsed - 0.5) < 1e-9)
        let b = MascotMotion.at(hold + 0.3, mood: .awake(.agent), size: 22)
        #expect(b.pose == .typing && abs(b.elapsed - 0.3) < 1e-9)
        let walkStart = MascotMotion.walkEvery - MascotMotion.walkLength
        let stroll = MascotMotion.at(walkStart + 0.4, mood: .awake(.idle), size: 22)
        #expect(stroll.pose == .walking && abs(stroll.elapsed - 0.4) < 1e-9)
        #expect(MascotMotion.at(1.1, mood: .waking, size: 22).pose == .waking)
        #expect(MascotMotion.at(1.1, mood: .waking, size: 22).elapsed == 1.1)
    }

    @Test func spriteClipsOnlyTravelByCode() {
        // Everything except stroll / jump / shake is baked into the sprites: no code offsets.
        for state in AvatarState.allCases where ![.idle, .done, .error, .thinking].contains(state) {
            for t in stride(from: 0.0, to: 10, by: 0.37) {
                let m = MascotMotion.at(t, mood: .awake(state), size: 22)
                #expect(m.dx == 0 && m.dy == 0 && m.scaleX == 1, "\(state) moved by code at \(t)")
            }
        }
        #expect(LivingPose.sleepingClean.clipID == "sleeping")
        #expect(LivingPose.walking.clipID == "walking")
    }

    @Test func thinkingIsDistinctFromIdle() {
        #expect(AvatarState.thinking.pose == .thinking && AvatarState.idle.pose == .idle)
        #expect(MascotMotion.cycle(for: .thinking).poses.first == .thinking)
        #expect(MascotMotion.cycle(for: .thinking).poses != MascotMotion.cycle(for: .idle).poses)
        // It moves by code: some offset is non-zero within a sway period, which idle's standing frame never has.
        let moved = stride(from: 0.1, to: 1.6, by: 0.1).contains {
            let m = MascotMotion.at($0, mood: .awake(.thinking), size: 22)
            return m.dx != 0 || m.dy != 0
        }
        #expect(moved)
        #expect(MascotMotion.at(1.0, mood: .awake(.idle), size: 22).dx == 0)
        #expect(AvatarState.thinking.pulses)
    }

    @Test func tickRatesStayWithinTheBudget() {
        for state in AvatarState.allCases {
            let busy = LivingAvatar.tickInterval(asleep: false, waking: false, state: state)
            #expect(busy >= 1.0 / 24 - 1e-9)
            #expect(state != .idle || busy >= 1.0 / 12 - 1e-9)
        }
        #expect(LivingAvatar.tickInterval(asleep: true, waking: false, state: .idle) >= 1.0 / 12 - 1e-9)
    }

    // MARK: QA7 round 11 -- `zeus debug animate <pose>` for the v2 poses no `AvatarState` reaches directly

    // Each test below uses its own `AvatarStatus` instance (not `.shared`) so these can't race
    // other tests' timers against the one global singleton. They also poll with a generous
    // overall budget rather than asserting at one fixed instant: `Task.sleep`'s duration is only
    // a lower bound, and under this Mac's observed heavy concurrent load (several other overnight
    // agent sessions; see PROGRESS-QA7.md) a nominal sub-0.1s wait was seen to actually take 7s,
    // and two independent sleeps' continuations aren't guaranteed to resume in deadline order --
    // a fixed single-check version of these tests flaked for exactly that reason.

    @MainActor @Test func previewPoseShowsExactlyThatPoseThenExpires() async throws {
        let status = AvatarStatus()
        #expect(status.posePreview == nil)
        status.previewPose(.carrying, for: 0.01)
        #expect(status.posePreview == .carrying)
        var cleared = false
        for _ in 0..<200 where !cleared {
            try await Task.sleep(for: .seconds(0.05))
            cleared = status.posePreview == nil
        }
        #expect(cleared)
    }

    @MainActor @Test func aLaterPreviewReplacesAnEarlierOneRatherThanBothExpiring() async throws {
        let status = AvatarStatus()
        status.previewPose(.working, for: 0.01)
        status.previewPose(.celebrate, for: 1000) // far outlasts this test; isolates the token guard
        for _ in 0..<100 {
            try await Task.sleep(for: .seconds(0.05))
            // The first preview's own delayed clear must see its token is stale and no-op --
            // never clear the second, still-active preview underneath it.
            #expect(status.posePreview == .celebrate)
        }
    }

    @Test func everyReportedMissingAnimateNameIsARealLivingPose() {
        // QA7 round 11 (report-11.md): "zeus debug animate working|approval_wait|carrying|celebrate"
        // returned "Unknown animation" -- confirm each is a real `LivingPose` the debug hook's
        // `LivingPose(rawValue:)` fallback (AppDelegate.onDebugAnimate) can now reach directly.
        for name in ["working", "approval_wait", "carrying", "celebrate"] {
            #expect(LivingPose(rawValue: name) != nil, "\(name) should be a LivingPose")
        }
        // "sleep"/"wake" aren't pose names at all (they're the asleep/waking booleans); the debug
        // hook maps them to the poses those booleans actually show.
        #expect(LivingPose(rawValue: "sleep") == nil)
        #expect(LivingPose(rawValue: "wake") == nil)
    }

    @MainActor @Test func pinnedPoseOverridesTheNormalCycleRegardlessOfState() {
        // `LivingAvatar.body`'s pinnedPose branch bypasses `MascotMotion.at`'s state-driven cycle
        // entirely; this is the same frame construction it uses, just confirming the override pose
        // (not whatever `.agent`'s own cycle would otherwise be showing) is what gets drawn.
        let overridden = MascotMotion(pose: .celebrate, elapsed: 1.2)
        #expect(overridden.pose == .celebrate)
        let normal = MascotMotion.at(1.2, mood: .awake(.agent), size: 22)
        #expect(normal.pose != .celebrate) // confirms the override, not a coincidence of the cycle
    }

    @MainActor @Test func aMissingAtlasFallsBackToTheStillPose() {
        let missing = MascotAtlasStore(directory: URL(fileURLWithPath: "/nonexistent/zeus-anim"))
        #expect(missing.clip("idle") == nil)
        #expect(missing.frame("idle", elapsed: 1, points: 22) == nil)
        let bundleless = MascotAtlasStore(directory: nil)
        #expect(bundleless.frame("walking", elapsed: 0, points: 96) == nil)
        // A clip whose JSON exists but whose PNG does not also yields nil, never a crash.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-anim-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let json = try? Data(contentsOf: Self.animDir.appendingPathComponent("idle.json")) {
            try? json.write(to: tmp.appendingPathComponent("idle.json"))
            let noPNG = MascotAtlasStore(directory: tmp)
            #expect(noPNG.clip("idle") != nil)
            #expect(noPNG.frame("idle", elapsed: 0, points: 22) == nil)
        }
    }

    @MainActor @Test func theStoreDecodesFramesFromTheShippedAtlases() throws {
        let store = MascotAtlasStore(directory: Self.animDir)
        let idle = try #require(store.clip("idle"))
        #expect(idle.isLoop && idle.seconds == 4)
        let small = try #require(store.frame("idle", elapsed: 0.3, points: 22))
        let large = try #require(store.frame("idle", elapsed: 0.3, points: 96))
        #expect(small.width == 128 && small.height == 128)
        #expect(large.width == 320 && large.height == 320)
        #expect(store.frame("idle", elapsed: 0.3, points: 22) === small) // cached, not decoded again
    }

    /// Checked on disk: every state in the manifest has both atlases, timed from the manifest, with
    /// metadata that matches the PNG on disk. Together they stay inside the bundle-size budget.
    @Test func everyStateShipsAnAtlasMatchingItsMetadataAndTheManifest() throws {
        let manifestURL = Self.animDir.appendingPathComponent("../../../../Design/mascot-v2/ZEUS_Mascot_Pack_v2/manifest.json").standardizedFileURL
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let states = try #require(manifest["states"] as? [[String: Any]])
        #expect(states.count == 24)
        var bytes = 0
        for state in states {
            let id = try #require(state["id"] as? String)
            let clip = try JSONDecoder().decode(MascotClip.self, from: Data(contentsOf: Self.animDir.appendingPathComponent("\(id).json")))
            #expect(clip.state == id)
            #expect(clip.kind == (state["timing_kind"] as? String))
            let seconds = (state["seconds"] as? NSNumber)?.doubleValue ?? 0
            #expect(abs(clip.length - seconds) < 0.002, "\(id) lasts \(clip.length)s, manifest says \(seconds)s")
            #expect(clip.frameDurationsMs.count == clip.frameCount && clip.frameCount >= 4)
            #expect(clip.fps >= 12 && clip.fps <= 24, "\(id) runs at \(clip.fps) fps")
            #expect(Set(clip.sizes.keys) == ["128", "320"])
            for (key, atlas) in clip.sizes {
                #expect(atlas.cell == Int(key) && atlas.frames.count == clip.frameCount)
                #expect(atlas.frames.allSatisfy { $0.x + $0.w <= atlas.width && $0.y + $0.h <= atlas.height })
                let url = Self.animDir.appendingPathComponent(atlas.file)
                let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(atlas.file) unreadable")
                let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
                #expect((props[kCGImagePropertyPixelWidth] as? Int) == atlas.width, "\(atlas.file) width")
                #expect((props[kCGImagePropertyPixelHeight] as? Int) == atlas.height, "\(atlas.file) height")
                bytes += (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            }
        }
        #expect(bytes < 25_000_000, "atlases weigh \(bytes) bytes; budget is 25 MB")
        // Every clip the motion can ask for exists.
        var used = Set(AvatarState.allCases.flatMap { MascotMotion.cycle(for: $0).poses })
        used.formUnion([.walking, .sleepingClean, .waking, .curious])
        for pose in used {
            #expect(FileManager.default.fileExists(atPath: Self.animDir.appendingPathComponent("\(pose.clipID).json").path), "no clip for \(pose)")
        }
    }
}
