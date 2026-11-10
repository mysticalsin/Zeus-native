import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly cursor-follow export")
struct RecordlyCursorFollowTests {
    private var samples: [RecordlyCursorSample] {
        (0...120).map { index in
            RecordlyCursorSample(time: Double(index) / 30, point: CGPoint(x: 700 + Double(index) * 4, y: 540))
        }
    }

    @Test func exportedZoomFollowsTheSmoothedPath() throws {
        let path = RecordlyCursorFollowPath(samples: samples)
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let space = try #require(RecordlyExportPlan.CursorSpace(
            streamFrame: frame, displayBounds: frame, primaryHeight: 1080, pixelWidth: 1920, pixelHeight: 1080
        ))
        let region = RecordlyZoomRegion(start: 0, end: 5, center: samples[0].point, scale: 2)
        let before = RecordlyExportPlan.cropRect(at: 2, full: frame, regions: [region], space: space, followPath: path)
        let after = RecordlyExportPlan.cropRect(at: 3, full: frame, regions: [region], space: space, followPath: path)
        #expect(after.midX > before.midX + 80)
        #expect(abs(after.midX - (try #require(path.point(at: 3))).x) < 0.001)
        #expect(before.width == 960 && after.width == 960)
        #expect(frame.contains(before) && frame.contains(after))
        // Turning follow off preserves the authored click center.
        let fixed = RecordlyExportPlan.cropRect(at: 3, full: frame, regions: [region], space: space)
        #expect(fixed.midX == 700)
        // A path never grants coordinate authority or creates a zoom outside its region.
        #expect(RecordlyExportPlan.cropRect(at: 3, full: frame, regions: [region], space: nil, followPath: path) == frame)
        #expect(RecordlyExportPlan.cropRect(at: 6, full: frame, regions: [region], space: space, followPath: path) == frame)
    }

    @Test func pathIsContinuousAndRejectsNonFiniteSamples() throws {
        let invalid = [RecordlyCursorSample(time: .nan, point: .zero),
                       RecordlyCursorSample(time: 1, point: CGPoint(x: Double.infinity, y: 0))]
        let path = RecordlyCursorFollowPath(samples: invalid + samples)
        let before = try #require(path.point(at: 2 - 0.001))
        let after = try #require(path.point(at: 2 + 0.001))
        #expect(abs(after.x - before.x) < 1)
        #expect(path.point(at: .nan) == nil)
        #expect(RecordlyCursorFollowPath(samples: invalid).frameCount == 0)
    }

    @Test func longRecordingsKeepABoundedPath() {
        let path = RecordlyCursorFollowPath(samples: [
            RecordlyCursorSample(time: 0, point: .zero),
            RecordlyCursorSample(time: 21_600, point: CGPoint(x: 1000, y: 500)),
        ])
        #expect(path.frameCount <= RecordlyCursorFollowPath.maxFrameCount)
        #expect(path.frameCount > 0)
        let end = path.point(at: 21_602)
        #expect(abs((end?.x ?? 0) - 1000) < 1)
    }

    @Test func followPreferenceSurvivesRoundTripAndOldProjectsDecode() throws {
        let old = Data(#"{"preset":"hd1080","quality":"balanced","formats":["mp4"]}"#.utf8)
        #expect(try JSONDecoder().decode(RecordlyExportSettings.self, from: old).followCursor)
        let off = RecordlyExportSettings(followCursor: false)
        let encoded = try JSONEncoder().encode(off)
        #expect(try JSONDecoder().decode(RecordlyExportSettings.self, from: encoded) == off)
    }
}
