import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite struct RecordlyExportPlanTests {
    private let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let space = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func region(start: Double = 2, end: Double = 6, center: CGPoint = CGPoint(x: 960, y: 540), scale: Double = 2) -> RecordlyZoomRegion {
        RecordlyZoomRegion(start: start, end: end, center: center, scale: scale)
    }

    // MARK: Size

    @Test func sizes16x9() {
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 2560, sourceHeight: 1440, longSide: 1920) == .init(width: 1920, height: 1080))
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 2560, sourceHeight: 1440, longSide: 3840) == .init(width: 3840, height: 2160))
    }

    @Test func sizes16x10() {
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 2880, sourceHeight: 1800, longSide: 1920) == .init(width: 1920, height: 1200))
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 2880, sourceHeight: 1800, longSide: 3840) == .init(width: 3840, height: 2400))
    }

    @Test func sizesPortrait() {
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 1080, sourceHeight: 1920, longSide: 1920) == .init(width: 1080, height: 1920))
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 1080, sourceHeight: 1920, longSide: 3840) == .init(width: 2160, height: 3840))
    }

    @Test func sizesAreEvenAndRejectBadSources() {
        let odd = RecordlyExportPlan.outputSize(sourceWidth: 1366, sourceHeight: 768, longSide: 1920)
        #expect(odd?.width == 1920)
        #expect(odd?.height == 1080)
        #expect((odd?.width ?? 1) % 2 == 0 && (odd?.height ?? 1) % 2 == 0)
        #expect(RecordlyExportPlan.outputSize(sourceWidth: 0, sourceHeight: 100, longSide: 1920) == nil)
        #expect(RecordlyExportPlan.outputSize(sourceWidth: .nan, sourceHeight: 100, longSide: 1920) == nil)
    }

    // MARK: Trim

    @Test func trimDefaultsToFullDuration() {
        #expect(RecordlyExportPlan.trimRange(trimStart: 0, trimEnd: nil, duration: 12) == .init(start: 0, end: 12))
    }

    @Test func trimClampsToDuration() {
        #expect(RecordlyExportPlan.trimRange(trimStart: -5, trimEnd: 99, duration: 12) == .init(start: 0, end: 12))
        #expect(RecordlyExportPlan.trimRange(trimStart: 3, trimEnd: 8, duration: 12) == .init(start: 3, end: 8))
    }

    @Test func trimRejectsEmptyOrInvertedRanges() {
        #expect(RecordlyExportPlan.trimRange(trimStart: 5, trimEnd: 5, duration: 12) == nil)
        #expect(RecordlyExportPlan.trimRange(trimStart: 8, trimEnd: 3, duration: 12) == nil)
        #expect(RecordlyExportPlan.trimRange(trimStart: 20, trimEnd: nil, duration: 12) == nil)
        #expect(RecordlyExportPlan.trimRange(trimStart: 0, trimEnd: nil, duration: 0) == nil)
    }

    // MARK: Crop

    @Test func cropOutsideRegionIsFullFrame() {
        let regions = [region()]
        #expect(RecordlyExportPlan.cropRect(at: 1, full: full, regions: regions, cursorSpace: space) == full)
        #expect(RecordlyExportPlan.cropRect(at: 7, full: full, regions: regions, cursorSpace: space) == full)
    }

    @Test func cropInsideRegionIsFullyZoomed() {
        let crop = RecordlyExportPlan.cropRect(at: 4, full: full, regions: [region()], cursorSpace: space)
        #expect(abs(crop.width - 960) < 0.001)
        #expect(abs(crop.height - 540) < 0.001)
        #expect(abs(crop.midX - 960) < 0.001)
        #expect(abs(crop.midY - 540) < 0.001)
    }

    @Test func easingBoundsAndMidpoint() {
        let r = region()
        #expect(RecordlyExportPlan.zoomWeight(at: 2, region: r) == 0)
        #expect(RecordlyExportPlan.zoomWeight(at: 6, region: r) == 0)
        #expect(abs(RecordlyExportPlan.zoomWeight(at: 2.15, region: r) - 0.5) < 1e-9)
        #expect(abs(RecordlyExportPlan.zoomWeight(at: 5.85, region: r) - 0.5) < 1e-9)
        #expect(RecordlyExportPlan.zoomWeight(at: 2.5, region: r) == 1)
        #expect(RecordlyExportPlan.zoomWeight(at: 1.9, region: r) == 0)
        let mid = RecordlyExportPlan.cropRect(at: 2.15, full: full, regions: [r], cursorSpace: space)
        #expect(abs(mid.width - 1280) < 0.001) // scale 1.5
    }

    @Test func easingIsMonotonicOnRampUp() {
        let r = region()
        var last = -1.0
        for step in 0...30 {
            let weight = RecordlyExportPlan.zoomWeight(at: 2 + Double(step) * 0.01, region: r)
            #expect(weight >= last)
            last = weight
        }
    }

    @Test func shortRegionStaysContinuousAndBelowFull() {
        let r = region(start: 1, end: 1.4)
        let peak = RecordlyExportPlan.zoomWeight(at: 1.2, region: r)
        #expect(peak > 0 && peak < 1)
    }

    @Test func cropWithoutCursorSpaceDoesNotZoom() {
        #expect(RecordlyExportPlan.cropRect(at: 4, full: full, regions: [region()], cursorSpace: nil) == full)
    }

    @Test func cropFlipsYAndClampsToFrame() {
        // Global y-up (200, 1000) is near the top of a 1080-high space, so the crop hugs the top-left corner.
        let r = region(center: CGPoint(x: 200, y: 1000))
        let crop = RecordlyExportPlan.cropRect(at: 4, full: full, regions: [r], cursorSpace: space)
        #expect(crop.minX >= 0 && crop.minY >= 0)
        #expect(crop.maxX <= full.maxX && crop.maxY <= full.maxY)
        #expect(abs(crop.minY) < 0.001)
        #expect(abs(crop.minX - 0) < 0.001)
    }

    @Test func cropOffsetsByCursorSpaceOrigin() {
        let shifted = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let r = region(center: CGPoint(x: -960, y: 540))
        let crop = RecordlyExportPlan.cropRect(at: 4, full: full, regions: [r], cursorSpace: shifted)
        #expect(abs(crop.midX - 960) < 0.001)
    }

    // MARK: Cursor space

    /// A 1920x1080 display stacked above a 1920x1080 primary. ScreenCaptureKit reports it top-left/y-down at y = -1080.
    private func aboveSpace(pixelWidth: Int = 1920, pixelHeight: Int = 1080) -> RecordlyExportPlan.CursorSpace? {
        let frame = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        return RecordlyExportPlan.CursorSpace(
            streamFrame: frame, displayBounds: frame, primaryHeight: 1080, pixelWidth: pixelWidth, pixelHeight: pixelHeight
        )
    }

    @Test func cursorSpaceFlipsIntoAppKitPoints() throws {
        let space = try #require(aboveSpace())
        #expect(space.frame == CGRect(x: 0, y: 1080, width: 1920, height: 1080))
    }

    @Test func offCenterZoomMapsThroughProductionPath() throws {
        let space = try #require(aboveSpace())
        // Video point (1200, 700) from the top-left is AppKit (1200, 2160 - 700) on the display above the primary.
        let r = region(center: CGPoint(x: 1200, y: 1460))
        let crop = RecordlyExportPlan.cropRect(at: 4, full: full, regions: [r], space: space)
        #expect(abs(crop.width - 960) < 0.001 && abs(crop.height - 540) < 0.001)
        #expect(abs(crop.midX - 1200) < 0.001)
        #expect(abs(crop.midY - 700) < 0.001)
        #expect(crop != full)
    }

    @Test func offCenterZoomScalesToVideoPixels() throws {
        let space = try #require(aboveSpace())
        let retina = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let r = region(center: CGPoint(x: 1200, y: 1460))
        let crop = RecordlyExportPlan.cropRect(at: 4, full: retina, regions: [r], space: space)
        #expect(abs(crop.midX - 2400) < 0.001)
        #expect(abs(crop.midY - 1400) < 0.001)
        #expect(abs(crop.width - 1920) < 0.001)
    }

    @Test func missingOrMismatchedSpaceDoesNotZoom() throws {
        let r = region(center: CGPoint(x: 1200, y: 1460))
        #expect(RecordlyExportPlan.cropRect(at: 4, full: full, regions: [r], space: nil) == full)
        let portrait = try #require(aboveSpace(pixelWidth: 1080, pixelHeight: 1920))
        #expect(RecordlyExportPlan.cropRect(at: 4, full: full, regions: [r], space: portrait) == full)
    }

    @Test func cursorSpaceRejectsUnverifiedFrames() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let elsewhere = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        #expect(RecordlyExportPlan.CursorSpace(streamFrame: frame, displayBounds: elsewhere, primaryHeight: 1080, pixelWidth: 1920, pixelHeight: 1080) == nil)
        #expect(RecordlyExportPlan.CursorSpace(streamFrame: frame, displayBounds: frame, primaryHeight: 0, pixelWidth: 1920, pixelHeight: 1080) == nil)
        #expect(RecordlyExportPlan.CursorSpace(streamFrame: frame, displayBounds: frame, primaryHeight: 1080, pixelWidth: 0, pixelHeight: 1080) == nil)
        #expect(RecordlyExportPlan.CursorSpace(streamFrame: .zero, displayBounds: .zero, primaryHeight: 1080, pixelWidth: 1920, pixelHeight: 1080) == nil)
    }

    @Test func pendingSpaceCompletesWithVideoSize() throws {
        let bounds = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let pending = try #require(RecordlyExportPlan.CursorSpace.Pending(displayBounds: bounds, primaryHeight: 1080))
        let space = try #require(pending.completed(pixelWidth: 3840, pixelHeight: 2160))
        #expect(space.frame == CGRect(x: 0, y: 1080, width: 1920, height: 1080))
        #expect(pending.completed(pixelWidth: 1080, pixelHeight: 1920) == nil)
        #expect(pending.completed(pixelWidth: 0, pixelHeight: 1080) == nil)
    }

    @Test func pendingSpaceIsDroppedWhenDisplayMoved() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let pending = try #require(RecordlyExportPlan.CursorSpace.Pending(displayBounds: bounds, primaryHeight: 1080))
        #expect(pending.verified(currentBounds: bounds, currentPrimaryHeight: 1080) == pending)
        #expect(pending.verified(currentBounds: bounds.offsetBy(dx: 1920, dy: 0), currentPrimaryHeight: 1080) == nil)
        #expect(pending.verified(currentBounds: bounds, currentPrimaryHeight: 900) == nil)
        #expect(RecordlyExportPlan.CursorSpace.Pending(displayBounds: .zero, primaryHeight: 1080) == nil)
    }

    // MARK: GIF

    @Test func gifFrameCountFollowsRate() {
        let schedule = RecordlyExportPlan.gifSchedule(range: .init(start: 2, end: 12), frameRate: 15)
        #expect(schedule?.times.count == 150)
        #expect(schedule?.times.first == 2)
        #expect(schedule?.truncated == false)
        #expect(abs((schedule?.frameDelay ?? 0) - 1.0 / 15) < 1e-12)
    }

    @Test func gifCapsAtThirtySecondsAndSixHundredFrames() {
        let long = RecordlyExportPlan.gifSchedule(range: .init(start: 0, end: 100), frameRate: 20)
        #expect(long?.times.count == 600)
        #expect(long?.truncated == true)
        let slow = RecordlyExportPlan.gifSchedule(range: .init(start: 0, end: 40), frameRate: 10)
        #expect(slow?.times.count == 300)
        #expect(slow?.truncated == true)
        let last = long?.times.last ?? 0
        #expect(last < 30)
    }

    @Test func gifScheduleHasAtLeastOneFrameAndRejectsBadRate() {
        #expect(RecordlyExportPlan.gifSchedule(range: .init(start: 0, end: 0.1), frameRate: 10)?.times.count == 1)
        #expect(RecordlyExportPlan.gifSchedule(range: .init(start: 0, end: 5), frameRate: 0) == nil)
    }

    // MARK: Naming

    @Test func fileNameFormatAndSafety() throws {
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 7
        components.hour = 9; components.minute = 5; components.second = 3
        var calendar = Calendar(identifier: .gregorian)
        let utc = try #require(TimeZone(identifier: "UTC"))
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: components))
        let name = RecordlyExportPlan.fileName(date: date, fileExtension: "mp4", timeZone: utc)
        #expect(name == "Recordly 2026-11-07 09.05.03.mp4")
        #expect(!name.contains("/") && !name.contains(":"))
        #expect(RecordlyExportPlan.fileName(date: date, fileExtension: "gif", timeZone: utc, collisionIndex: 2) == "Recordly 2026-11-07 09.05.03 2.gif")
        let hostile = RecordlyExportPlan.fileName(date: date, fileExtension: "../x:y", timeZone: utc)
        #expect(!hostile.contains("/") && !hostile.contains(":") && !hostile.contains(".."))
    }

    @Test func outputDirectoryIsUnderMovies() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(RecordlyExportPlan.outputDirectory(home: home).path == "/Users/someone/Movies/Zeus Recordly")
    }
}
