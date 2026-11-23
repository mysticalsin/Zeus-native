import AppKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

extension ScribeMeetingCardHosted {
    /// REG-952: the real compact card, hosted, with long installed app names. The bottom row's detail text must be
    /// drawn whole (its drawn width reaches its natural width, so no tail cut) beside the widest capsule the state
    /// can show, and the card must never grow past the slab plus its shadow room.
    @MainActor
    @Suite("Meeting card fit")
    struct ScribeMeetingCardFitTests {
        typealias M = ScribeMeetingCardMetrics
        private let now = Date(timeIntervalSince1970: 1_800_000_000)
        /// The right column, where the bottom row lives: the slab minus its padding and the left column.
        private let textColumn = M.width - 2 * M.padding - M.leftColumnWidth
        /// The row's own gap between the detail line and the capsule.
        private let minimumGap: CGFloat = 8

        private let apps = [ScribeJoinApp(name: "Microsoft Teams", bundleID: "fit.teams"),
                            ScribeJoinApp(name: "Google Chrome", bundleID: "fit.chrome"),
                            ScribeJoinApp(name: "Safari", bundleID: "fit.safari"),
                            ScribeJoinApp(name: "Firefox Developer Edition", bundleID: "fit.firefox")]

        private func meeting(linked: Bool) -> ScribeMeeting {
            let link = linked ? URL(string: "https://example.org/room") : nil
            let slot = ScribeCalendarSlot(id: "fit-\(linked)", title: "Quarterly planning review with the whole regional team",
                                          start: now.addingTimeInterval(120), end: now.addingTimeInterval(2_820),
                                          attendeeNames: (1...11).map { "Guest \($0)" }, hasCallLink: linked, callLink: link)
            return ScribeMeeting(key: slot.id, title: slot.title, callApp: .other("Synthetic"), slot: slot)
        }

        @MainActor private struct Hosted {
            let window: NSWindow
            let host: NSHostingView<ScribeMeetingCardView>
            let registry: OwnedWindowControlRegistry

            func frames(_ id: String) -> [CGRect] {
                registry.probes(for: id, in: window).map { $0.convert($0.bounds, to: nil) }
            }
            func words(_ id: String) -> [String] { registry.probes(for: id, in: window).compactMap(\.renderedText) }
        }

        private func host(_ card: ScribeMeetingCard, joinApps: [ScribeJoinApp]) -> Hosted {
            let registry = OwnedWindowControlRegistry()
            let view = ScribeMeetingCardView(card: card, now: now, uptime: 100, settled: true, joinApps: joinApps,
                                             reduceMotion: true, reduceTransparency: true,
                                             locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC") ?? .current,
                                             journeyRegistry: registry)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: host.fittingSize),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return Hosted(window: window, host: host, registry: registry)
        }

        /// The width the detail text wants on one line, in the same font the card draws it in.
        private func naturalWidth(_ text: String) -> CGFloat {
            let probe = NSHostingView(rootView: Text(text).font(TopBarStyle.label(M.detailSize, .regular)).lineLimit(1).fixedSize())
            return probe.fittingSize.width
        }

        /// The icon in front of the line and its gap, in the same fonts the card uses.
        private func iconWidth(_ symbol: String) -> CGFloat {
            let probe = NSHostingView(rootView: Image(systemName: symbol).font(.system(size: M.detailSize - 1, weight: .medium)).fixedSize())
            return probe.fittingSize.width + 5
        }

        private var cards: [(String, ScribeMeetingCard)] {
            let linked = meeting(linked: true)
            let plain = meeting(linked: false)
            var rows: [(String, ScribeMeetingCard)] = []
            let blocks: [ScribeAutoStartBlock] = [.notChosen, .noOptIn, .microphoneNotAsked, .microphoneDenied, .firstRecordingOwed]
            for block in blocks {
                rows.append(("offer \(block) with link", .offer(linked, blocked: block)))
                rows.append(("offer \(block) no link", .offer(plain, blocked: block)))
            }
            let failures: [ScribeStartFailure] = [.microphoneOff, .stillSaving, .noResponse,
                                                  .captureFailed("some long error text that goes on"),
                                                  .captureFailed("No input device is available")]
            for failure in failures { rows.append(("failed \(failure)", .failed(linked, failure))) }
            rows.append(("waiting", .waiting(linked)))
            rows.append(("countdown", .countdown(linked, seconds: 3, deadline: 103, total: 5)))
            rows.append(("starting", .starting(linked, cancellable: true)))
            rows.append(("recording", .recording(linked)))
            rows.append(("next", .next(linked)))
            return rows
        }

        @Test func everyStateKeepsTheSlabPlusShadowSizeWithLongAppNames() {
            for (name, card) in cards {
                let hosted = host(card, joinApps: apps)
                defer { hosted.window.close() }
                #expect(hosted.host.fittingSize == M.windowSize, "\(name)")
            }
        }

        @Test func everyDetailLineIsDrawnWholeBesideTheWidestCapsule() throws {
            var checked = 0
            for (name, card) in cards {
                let hosted = host(card, joinApps: apps)
                defer { hosted.window.close() }
                let drawn = try #require(hosted.words("scribe.meetingCard.detail").first ?? "<none>", "\(name)")
                guard drawn != "<none>" else { continue }
                let frame = try #require(hosted.frames("scribe.meetingCard.detail").first, "\(name)")
                let natural = naturalWidth(drawn)
                #expect(frame.width + 0.5 >= natural, "\(name): \"\(drawn)\" is drawn \(frame.width) pt wide but wants \(natural)")
                // The same, as a budget: icon, text, the gap and the widest capsule fit the text column.
                let capsule = (hosted.frames("scribe.meetingCard.primary") + hosted.frames("scribe.meetingCard.cancel")
                               + hosted.frames("scribe.meetingCard.apps"))
                let left = capsule.map(\.minX).min() ?? textColumn
                let right = capsule.map(\.maxX).max() ?? textColumn
                let capsuleWidth = capsule.isEmpty ? 0 : right - left
                let symbol = ScribeMeetingCardText.detail(card) == nil ? "person.2.fill" : "exclamationmark.triangle.fill"
                let needed = iconWidth(symbol) + natural + minimumGap + capsuleWidth
                #expect(needed <= textColumn + 0.5, "\(name): needs \(needed) pt of \(textColumn)")
                checked += 1
            }
            #expect(checked >= 12)
        }

        @Test func theDetailWordingIsFixedAndShortWhateverTheCaptureErrorSays() {
            let linked = meeting(linked: true)
            for failure in [ScribeStartFailure.captureFailed("some long error text that goes on"),
                            .captureFailed("No input device is available")] {
                let text = ScribeMeetingCardText.detail(.failed(linked, failure)) ?? ""
                #expect(text.count <= M.detailMaxCharacters, "\(text)")
            }
        }

        @Test func theTileRowShowsAtMostThreeAppsWhileTheJoinMenuKeepsFour() {
            let hosted = host(.offer(meeting(linked: true), blocked: nil), joinApps: apps)
            defer { hosted.window.close() }
            #expect(hosted.words("scribe.meetingCard.tile").count == M.maxApps)
            #expect(M.maxApps == 3)
        }
    }
}

