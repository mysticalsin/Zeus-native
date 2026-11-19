import AppKit
import SwiftUI
import Testing
@testable import Zeus

/// While a page leaves (80 ms fade) it must overlap the new page, not sit above it and push it down.
@Suite("Page switch layout")
@MainActor
struct PageSwitchLayoutTests {
    private struct FramesKey: PreferenceKey {
        nonisolated(unsafe) static var defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
    }

    private struct Tagged: View {
        let tag: Int, height: CGFloat
        var body: some View {
            Color.clear.frame(height: height)
                .background(GeometryReader { Color.clear.preference(key: FramesKey.self, value: [tag: $0.frame(in: .named("root"))]) })
        }
    }

    private final class Frames { var value: [Int: CGRect] = [:] }

    private func layout(_ pages: [(tag: Int, height: CGFloat)]) -> [Int: CGRect] {
        let frames = Frames()
        let root = PageStack { ForEach(pages, id: \.tag) { Tagged(tag: $0.tag, height: $0.height) } }
            .frame(width: 400, alignment: .top)
            .coordinateSpace(name: "root")
            .onPreferenceChange(FramesKey.self) { frames.value = $0 }
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        return frames.value
    }

    @Test func theNewPageStaysPutWhileTheOldOneLeavesOverIt() {
        let alone = layout([(2, 100)])
        let during = layout([(1, 300), (2, 100)])
        let newAlone = try? #require(alone[2])
        let newDuring = try? #require(during[2])
        #expect(newAlone != nil && newDuring != nil)
        #expect(newDuring?.minY == 0, "the new page starts at the top, not under the old one")
        #expect(newDuring == newAlone, "the new page does not move while the old one leaves")
        #expect(during[1]?.minY == 0, "the old page overlaps from the top")
    }

    @Test func thePageSwitchUsesTheOverlapAndALeavingPageTakesNoHits() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zeus/TopBar/TopBarViews.swift"), encoding: .utf8)
        #expect(source.contains("PageSwitcher(key: topBar.selectedTab"))
        #expect(source.contains(".allowsHitTesting(!leaving)"))
        #expect(source.contains("Motion.pageOut"))
    }
}
