import AppKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// The glass card's look, read from a hosted view: its size, its two surfaces and the settings it follows.
@MainActor
@Suite("Meeting card view")
struct ScribeMeetingCardViewTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting() -> ScribeMeeting {
        let slot = ScribeCalendarSlot(id: "view", title: "View", start: now.addingTimeInterval(120), end: now.addingTimeInterval(2_820),
                                      attendeeNames: ["Ana"], hasCallLink: true, callLink: URL(string: "https://example.org/room"))
        return ScribeMeeting(key: "view", title: "View", callApp: .other("Synthetic"), slot: slot)
    }

    private func host(reduceTransparency: Bool? = nil, reduceMotion: Bool? = nil) -> (NSWindow, NSHostingView<ScribeMeetingCardView>) {
        let view = ScribeMeetingCardView(card: .offer(meeting(), blocked: nil), now: now, uptime: 100, settled: true,
                                         reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: host.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }

    /// The alpha at a point of the slab that holds no text or control: the top edge of the left column.
    private func alpha(of host: NSView) throws -> Double {
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = Double(rep.pixelsWide) / Double(host.bounds.width)
        let x = Int((Double(ScribeMeetingCardMetrics.shadowRoom) + 70) * scale)
        let y = Int((Double(ScribeMeetingCardMetrics.shadowRoom) + 8) * scale)
        return Double(try #require(rep.colorAt(x: x, y: y)).alphaComponent)
    }

    @Test func theHostedCardIsTheSlabPlusItsShadowRoom() {
        let (window, host) = host()
        defer { window.close() }
        #expect(host.fittingSize == ScribeMeetingCardMetrics.windowSize)
    }

    @Test func reduceTransparencyChoosesTheOpaqueSurfaceAndNothingElseDoes() {
        #expect(ScribeMeetingCardSurface.resolve(reduceTransparency: true) == .opaque)
        #expect(ScribeMeetingCardSurface.resolve(reduceTransparency: false) == .blurred)
    }

    private func blurs(in view: NSView) -> [NSVisualEffectView] {
        (view as? NSVisualEffectView).map { [$0] } ?? [] + view.subviews.flatMap { blurs(in: $0) }
    }

    @Test func withReduceTransparencyTheSlabIsOpaqueAndWithoutItTheSystemBlursTheDesktopBehindIt() throws {
        let (solidWindow, solid) = host(reduceTransparency: true)
        defer { solidWindow.close() }
        solid.layoutSubtreeIfNeeded()
        #expect(abs(try alpha(of: solid) - 1) < 0.01, "an opaque deep blue surface")
        #expect(blurs(in: solid).isEmpty, "nothing of the desktop is asked for")
        let (glassWindow, glass) = host(reduceTransparency: false)
        defer { glassWindow.close() }
        glass.layoutSubtreeIfNeeded()
        let found = blurs(in: glass)
        #expect(found.count == 1)
        #expect(found.first?.blendingMode == .behindWindow, "the blur is of what is behind the window")
        #expect(found.first?.state == .active)
    }

    @Test func theRimStaysWhenTheSurfaceGoesOpaque() throws {
        // The rim runs on the slab's edge: the pixel on the top edge, at the middle, is lit in both surfaces.
        for reduce in [true, false] {
            let (window, host) = host(reduceTransparency: reduce)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = Double(rep.pixelsWide) / Double(host.bounds.width)
            let x = Int((Double(ScribeMeetingCardMetrics.shadowRoom) + Double(ScribeMeetingCardMetrics.width) / 2) * scale)
            var best = 0.0
            for y in Int(Double(ScribeMeetingCardMetrics.shadowRoom - 1) * scale)...Int((Double(ScribeMeetingCardMetrics.shadowRoom) + 3) * scale) {
                let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                best = max(best, Double(color.greenComponent * color.alphaComponent))
            }
            #expect(best > 0.5, "the rim is lit with reduceTransparency \(reduce)")
        }
    }

    @Test func reduceMotionAndTheSystemDefaultBothHostWithoutTheEntranceMoving() {
        for reduce in [true, false] {
            let (window, host) = host(reduceMotion: reduce)
            defer { window.close() }
            #expect(host.fittingSize == ScribeMeetingCardMetrics.windowSize)
        }
    }
}
