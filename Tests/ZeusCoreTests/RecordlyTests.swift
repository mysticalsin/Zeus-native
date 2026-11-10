import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite struct RecordlyZoomTests {
    @Test func autoRegionsFromClicks() throws {
        let clicks = [
            RecordlyCursorSample(time: 1.0, point: CGPoint(x: 100, y: 200), clicked: true),
            RecordlyCursorSample(time: 1.2, point: CGPoint(x: 101, y: 201), clicked: true),
            RecordlyCursorSample(time: 4.0, point: CGPoint(x: 400, y: 300), clicked: true),
        ]
        let regions = RecordlyZoomPlanner.regions(from: clicks)
        try #require(regions.count == 2)
        #expect(regions[0].center == clicks[0].point)
        #expect(regions[1].center == clicks[2].point)
    }

    @Test func overlappingClickIsSkipped() {
        let clicks = [
            RecordlyCursorSample(time: 1.0, point: CGPoint(x: 100, y: 200), clicked: true),
            RecordlyCursorSample(time: 1.2, point: CGPoint(x: 101, y: 201), clicked: true),
            RecordlyCursorSample(time: 3.0, point: CGPoint(x: 400, y: 300), clicked: true),
        ]
        let regions = RecordlyZoomPlanner.regions(from: clicks)
        #expect(regions.count == 1)
        #expect(regions.first?.center == clicks[0].point)
    }

    @Test func cropRectScalesInward() {
        let full = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let crop = RecordlyZoomPlanner.cropRect(full: full, center: CGPoint(x: 500, y: 400), scale: 2)
        #expect(crop.width == 500)
        #expect(crop.height == 400)
    }

    @Test func regionLookupAtTime() {
        let region = RecordlyZoomRegion(start: 1, end: 3, center: .zero, scale: 2)
        #expect(RecordlyZoomPlanner.region(at: 2, in: [region]) == region)
        #expect(RecordlyZoomPlanner.region(at: 4, in: [region]) == nil)
    }
}

@Suite struct RecordlyCursorSmootherTests {
    @Test func smoothPathEndsNearTarget() {
        let samples = [
            RecordlyCursorSample(time: 0, point: .zero),
            RecordlyCursorSample(time: 0.5, point: CGPoint(x: 200, y: 0)),
        ]
        let path = RecordlyCursorSmoother.smooth(samples: samples, dt: 1.0 / 30.0)
        #expect(!path.isEmpty)
        let last = path.last!.point
        #expect(abs(last.x - 200) < 5)
    }

    @Test func nonPositiveOrNonFiniteDtTerminatesWithRawSamples() {
        let samples = [
            RecordlyCursorSample(time: 0.5, point: CGPoint(x: 200, y: 0)),
            RecordlyCursorSample(time: 0, point: .zero),
        ]
        for dt in [0.0, -1.0 / 60.0, Double.nan, Double.infinity] {
            let path = RecordlyCursorSmoother.smooth(samples: samples, dt: dt)
            #expect(path.map(\.time) == [0, 0.5])
            #expect(path.map(\.point) == [.zero, CGPoint(x: 200, y: 0)])
        }
        #expect(RecordlyCursorSmoother.smooth(samples: [], dt: 0).isEmpty)
    }

    @Test func loopClosesPath() {
        let samples = [
            RecordlyCursorSample(time: 0, point: CGPoint(x: 10, y: 10)),
            RecordlyCursorSample(time: 1, point: CGPoint(x: 200, y: 50)),
        ]
        let looped = RecordlyCursorSmoother.loop(samples: samples)
        #expect(looped.count > samples.count)
        #expect(looped.last?.point == samples.first?.point)
    }
}

@Suite struct RecordlyExportSettingsTests {
    @Test func parseFormatsList() {
        let formats = RecordlyExportSettings.parseFormats("mp4,gif")
        #expect(formats == [.mp4, .gif])
    }

    @Test func presetLongSide() {
        #expect(RecordlyVideoPreset.hd1080.longSide == 1920)
        #expect(RecordlyVideoPreset.uhd4K.longSide == 3840)
    }
}

@Suite struct RecordlyProjectTests {
    @Test func roundTripJSON() throws {
        // iso8601 coding keeps whole seconds only, so a fresh Date() would not round-trip.
        var project = RecordlyProject(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .display(id: 1), rawMediaPath: "/tmp/x.mp4")
        project.cursorSamples = [RecordlyCursorSample(time: 0.5, point: CGPoint(x: 1, y: 2), clicked: true)]
        project.applyAutoZoomFromClicks()
        #expect(project.zoomRegions.count == 1)
        let data = try project.encoded()
        let decoded = try RecordlyProject.decode(data)
        #expect(decoded == project)
    }
}

@Suite struct RecordlyCameraBubbleTests {
    @Test func idleGrowsBubble() {
        #expect(RecordlyCameraBubbleScale.scale(lastMove: 0, now: 2, moving: false) == RecordlyCameraBubbleScale.idleScale)
        #expect(RecordlyCameraBubbleScale.scale(lastMove: 0, now: 0.1, moving: true) == RecordlyCameraBubbleScale.activeScale)
    }
}

@Suite struct RecordlyDebugPlanTests {
    @Test func parseArguments() {
        let plan = RecordlyDebugPlanParser.parse("--seconds 5 --window settings --no-mic --export mp4,gif")
        #expect(plan.seconds == 5)
        #expect(plan.windowName == "settings")
        #expect(plan.noMic)
        #expect(plan.exportFormats == [.mp4, .gif])
    }
}

@Suite struct RecordlySampleRouteTests {
    @Test func screenAndSystemAudioStayOnSeparateTracks() {
        #expect(RecordlySampleRoute.track(for: .screen) == .video)
        #expect(RecordlySampleRoute.track(for: .systemAudio) == .audio)
        #expect(RecordlySampleRoute.track(for: .microphone) == .drop)
    }
}

@Suite struct RecordlyExclusionTests {
    @Test func respectsScreenSharePolicy() {
        let hidden = RecordlyCaptureExclusions.fromScreenSharePolicy(showInScreenSharing: false, meetingActive: false, teleprompterSessionHidden: false)
        #expect(hidden.excludeZeusWindows)
        let visible = RecordlyCaptureExclusions.fromScreenSharePolicy(showInScreenSharing: true, meetingActive: false, teleprompterSessionHidden: false)
        #expect(!visible.excludeZeusWindows)
    }
}

@Suite struct RecordlyTopBarTabTests {
    @Test func recordlyTabMetadata() {
        #expect(TopBarTab.recordly.title == "Recordly")
        #expect(TopBarTab.recordly.symbol == "record.circle")
    }
}
