import SwiftUI
import ZeusCore

extension TopBarModel {
    func receiveWidgetTap(_ target: TopBarWidgetTarget, count: Int = 1) {
        widgetClicks.tap(target, count: count) { [weak self] effect in
            self?.performWidgetClick(effect)
        }
    }

    func receiveWidgetRightSwipe(_ target: TopBarWidgetTarget, distance: Double) {
        widgetClicks.rightSwipe(target, distance: distance) { [weak self] effect in
            self?.performWidgetClick(effect)
        }
    }

    func activateWidget(_ target: TopBarWidgetTarget) {
        widgetClicks.activate(target) { [weak self] effect in
            self?.performWidgetClick(effect)
        }
    }

    func showWidgetDetails(_ target: TopBarWidgetTarget) {
        guard let effect = widgetClicks.showDetails(target) else { return }
        performWidgetClick(effect)
    }

    /// One line for the details a right swipe embeds on the summary. The page itself stays put.
    func embeddedWidgetLine(_ target: TopBarWidgetTarget) -> String {
        switch target {
        case .play, .pause, .skip, .music, .nowPlaying:
            guard let playing = nowPlaying else { return "Nothing playing" }
            if playing.artist.isEmpty { return playing.title }
            return "\(playing.title), \(playing.artist)"
        case .calendar, .agenda, .month:
            let moment = Date()
            if let next = (events + calendarEvents).first(where: { $0.end > moment }) {
                return next.title
            }
            return "Nothing coming up"
        case .weather:
            guard let weather else { return weatherPlace.isEmpty ? "Weather" : weatherPlace }
            let place = weatherPlace.isEmpty ? weather.phrase : weatherPlace
            return "\(place), \(temperature(weather.temperature))"
        case .focus:
            switch focus.phase {
            case .idle: return "Ready"
            case .focus: return "Focusing"
            case .rest: return "Break"
            }
        case .agents:
            return "Agents"
        }
    }

    func performWidgetClick(_ effect: TopBarWidgetEffect) {
        switch effect {
        case .play:
            musicCommand(.play)
        case .pause:
            musicCommand(.pause)
        case .next:
            musicCommand(.next)
        case .refreshWeather:
            refreshWeather()
        case .toggleFocus:
            if focus.phase == .idle { focus.start() } else { focus.stop() }
        case .selectNextEvent:
            let moment = Date()
            if let next = events.first(where: { $0.end > moment }) {
                calendarDay = next.start
            }
        case .openDetails(let page):
            widgetClicks.embedded = nil
            showWidgetPage(page)
        case .embeddedDetails(let page):
            widgetClicks.embedded = page
        case .tripleClick:
            break
        }
    }

    private func showWidgetPage(_ page: TopBarWidgetDetails) {
        let tab: TopBarTab
        switch page {
        case .music: tab = .music
        case .calendar: tab = .calendar
        case .weather: tab = .weather
        case .focus: tab = .focus
        case .agents: tab = .agents
        }
        let reveal = {
            self.selectedTab = tab
            if TopBarWidgetClicks.revealsPanel(.openDetails(page)) {
                self.onOpenTab(tab)
            }
        }
        if TopBarWidgetClicks.detailsDuration(reduceMotion: Motion.reduced) == 0 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { reveal() }
        } else {
            reveal()
        }
    }
}

/// Click, double click, and triple click, plus a right swipe that embeds details. No hold: the menu stays
/// on the card row that already has it.
private struct TopBarWidgetTapModifier: ViewModifier {
    let target: TopBarWidgetTarget
    let model: TopBarModel
    @State private var embedded: TopBarWidgetDetails?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay(alignment: .bottomLeading) {
                if embedded != nil {
                    Text(model.embeddedWidgetLine(target))
                        .font(GlanceType.title)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Details")
                        .accessibilityValue(model.embeddedWidgetLine(target))
                }
            }
            .onTapGesture(count: 3) {
                setEmbedded(nil)
                model.receiveWidgetTap(target, count: 3)
            }
            .onTapGesture(count: 2) {
                setEmbedded(nil)
                model.receiveWidgetTap(target, count: 2)
            }
            .onTapGesture(count: 1) {
                setEmbedded(nil)
                model.receiveWidgetTap(target, count: 1)
            }
            .simultaneousGesture(DragGesture(minimumDistance: TopBarWidgetClicks.rightSwipeDistance).onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard TopBarWidgetClicks.isRightSwipe(dx: dx, dy: dy) else { return }
                model.receiveWidgetRightSwipe(target, distance: dx)
                setEmbedded(model.widgetClicks.embedded)
            })
            .accessibilityAction { model.activateWidget(target) }
            .accessibilityAction(named: "Show details") { model.showWidgetDetails(target) }
            .accessibilityAction(named: "Show embedded details") {
                model.receiveWidgetRightSwipe(target, distance: TopBarWidgetClicks.rightSwipeDistance)
                setEmbedded(model.widgetClicks.embedded)
            }
    }

    private func setEmbedded(_ page: TopBarWidgetDetails?) {
        if Motion.reduced {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { embedded = page }
        } else {
            embedded = page
        }
    }
}

extension View {
    /// A summary chip. One click waits out the window. A double click is more information. A triple click
    /// stays its own gesture. A right swipe embeds the details. This does not install a hold.
    func topBarWidgetTap(_ target: TopBarWidgetTarget, model: TopBarModel) -> some View {
        modifier(TopBarWidgetTapModifier(target: target, model: model))
    }
}
