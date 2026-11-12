import SwiftUI
import ZeusCore

/// The Memory window: pages on the left, one page on the right. Content state belongs to the
/// controller; keyboard focus stays with the native view.
struct WikiView: View {
    let controller: WikiController

    var body: some View {
        VStack(spacing: 0) {
            WikiTopBar(controller: controller)
            WikiBanners(controller: controller)
            HStack(spacing: 0) {
                WikiSidebar(controller: controller)
                    .frame(width: 270)
                Divider()
                WikiDetail(controller: controller)
            }
        }
        .background(Theme.storm)
        .preferredColorScheme(.dark)
        .sheet(item: Binding(get: { controller.vaultExport }, set: { controller.vaultExport = $0 })) { model in
            WikiMCPExportSheet(model: model) { controller.vaultExport = nil }
        }
        .sheet(isPresented: Binding(get: { controller.graphOpen }, set: { controller.graphOpen = $0 })) {
            WikiGraphView(controller: controller)
        }
    }
}

// MARK: Top bar

private struct WikiTopBar: View {
    let controller: WikiController

    var body: some View {
        HStack(spacing: 12) {
            Text("Memory")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.cloudPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("What Zeus learned from your saved meetings. Private notes are never read.")
                .font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Send to vault…") { controller.beginVaultExport() }
                .accessibilityHint("Choose Memory pages and review a new note before exporting to your configured vault.")
            Button("Update from meetings") { controller.refreshFromMeetings(force: true) }
                .disabled(controller.learningPaused)
                .accessibilityHint("Reads your saved meetings now and adds what they decided.")
            Toggle("Pause learning", isOn: Binding(
                get: { controller.learningPaused },
                set: { controller.setLearningPaused($0) }
            ))
            .toggleStyle(.switch)
            .foregroundStyle(Theme.cloudPrimary)
            .disabled(controller.settingsUnreadable)
            .accessibilityHint(controller.settingsUnreadable
                ? "Unavailable until you reset Memory's settings."
                : "While on, Zeus adds nothing new to Memory.")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct WikiBanners: View {
    let controller: WikiController

    var body: some View {
        VStack(spacing: 6) {
            if controller.settingsUnreadable {
                WikiBanner(
                    text: "Memory's settings couldn't be read, so learning stays paused. Deleting and forgetting meetings still work. Resetting keeps a copy of the unreadable file and turns learning on again.",
                    tint: Theme.ember,
                    dismiss: nil,
                    action: ("Reset settings…", { controller.requestReset() })
                )
            } else if controller.learningPaused {
                WikiBanner(text: "Learning is paused. Nothing new is added to Memory.", tint: Theme.sky, dismiss: nil)
            }
            if !controller.loadIssues.isEmpty {
                WikiBanner(
                    text: controller.loadIssues.joined(separator: " "),
                    tint: Theme.ember,
                    dismiss: { controller.dismissLoadIssues() }
                )
            }
            if let notice = controller.notice {
                WikiBanner(text: notice, tint: Theme.accent, dismiss: { controller.dismissNotice() })
            }
        }
        .padding(.horizontal, 14)
        .confirmationDialog(
            "Reset Memory's settings?",
            isPresented: Binding(
                get: { controller.confirmingResetSettings },
                set: { controller.confirmingResetSettings = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset and resume learning", role: .destructive) { controller.resetSettings() }
            Button("Cancel", role: .cancel) { controller.confirmingResetSettings = false }
        } message: {
            Text("The unreadable settings file is kept beside the new one. Meetings you forgot are still never learned from. Learning turns on again.")
        }
    }
}

private struct WikiBanner: View {
    let text: String
    let tint: Color
    let dismiss: (() -> Void)?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(tint).accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.run)
            }
            if let dismiss {
                Button("Dismiss", action: dismiss)
                    .accessibilityHint("Hides this message.")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.bubbleRadius).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }
}

// MARK: Sidebar

private struct WikiSidebar: View {
    let controller: WikiController
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search Memory", text: Binding(
                get: { controller.query },
                set: { controller.query = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .accessibilityLabel("Search Memory")
            .accessibilityIdentifier("memory.search")
            let pages = controller.visiblePages
            HStack {
                Text("\(pages.count) of \(controller.pages.count) pages")
                    .font(.caption).foregroundStyle(Theme.cloudSecondary)
                    .accessibilityIdentifier("memory.results")
                Spacer(minLength: 0)
                Button("Clear search") { controller.query = ""; searchFocused = true }
                    .font(.caption)
                    .disabled(controller.query.isEmpty)
                    .accessibilityIdentifier("memory.search.clear")
            }
            if pages.isEmpty {
                Text(controller.pages.isEmpty
                     ? "Nothing here yet. Decisions and action items from your finished meetings show up as pages."
                     : "No page matches your search.")
                    .font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(pages) { page in
                            WikiRow(page: page, selected: page.id == controller.selectedID) {
                                controller.select(page.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

private struct WikiRow: View {
    let page: WikiPage
    let selected: Bool
    let action: () -> Void

    private var summary: String {
        let scope = page.scope == .global ? "Global" : "Personal"
        let count = page.facts.count
        return "\(scope) · \(count) item\(count == 1 ? "" : "s")"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1)
                    Text(summary)
                        .font(.system(size: 10)).foregroundStyle(Theme.cloudSecondary)
                }
                Spacer(minLength: 0)
                if page.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.bubbleRadius)
                    .fill(selected ? Theme.accentDeep.opacity(0.6) : Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title), \(summary)\(page.pinned ? ", pinned" : "")")
        .accessibilityIdentifier("memory.page.\(page.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Detail

private struct WikiDetail: View {
    let controller: WikiController

    var body: some View {
        Group {
            if let page = controller.selectedPage {
                WikiPageDetail(controller: controller, page: page)
            } else {
                Text("Select a page to read or edit it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.cloudSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct WikiPageDetail: View {
    let controller: WikiController
    let page: WikiPage

    private var scopeText: String {
        guard page.scope == .global else { return "Personal" }
        var text = "Global"
        if let by = page.promotedBy { text += ", promoted by \(by)" }
        if let at = page.promotedAt { text += " on \(at.formatted(date: .abbreviated, time: .shortened))" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(page.title)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(scopeText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(page.scope == .global ? Theme.storm : Theme.cloudPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(page.scope == .global ? Theme.ember : Color.white.opacity(0.14)))
                    .accessibilityLabel("Scope: \(scopeText)")
                Spacer(minLength: 0)
            }
            if page.needsReview {
                WikiReviewBanner(controller: controller, reason: page.reviewReason ?? WikiPage.reviewReasonForgottenText)
            }
            TextEditor(text: Binding(
                get: { controller.draftBody },
                set: { controller.setDraftBody($0) }
            ))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.cloudPrimary)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Theme.bubbleRadius).fill(Color.white.opacity(0.06)))
            .frame(minHeight: 160)
            .accessibilityLabel("Page text, editable")
            .accessibilityIdentifier("memory.page.editor")
            .accessibilityHint("Changes are saved when you stop typing. Editing a global page makes it personal again.")
            if controller.promotionOpen {
                WikiPromotionPanel(controller: controller)
            }
            WikiSources(controller: controller, page: page)
            WikiRelatedPages(controller: controller)
            WikiActions(controller: controller, page: page)
        }
        .padding(14)
    }
}

private struct WikiReviewBanner: View {
    let controller: WikiController
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.ember).accessibilityHidden(true)
            Text("Needs review. \(reason) Check the text below and remove anything that should be forgotten. Until you do, this page can't be exported or made global.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.cloudPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("I've reviewed this") { controller.markReviewed() }
                .accessibilityHint("Confirms you checked this page. Export and promotion become available again.")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.bubbleRadius).fill(Theme.ember.opacity(0.18)))
        .accessibilityElement(children: .contain)
    }
}

private struct WikiSources: View {
    let controller: WikiController
    let page: WikiPage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Learned from")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudPrimary)
                .accessibilityAddTraits(.isHeader)
            if page.sources.isEmpty {
                Text("No sources.").font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(page.sources, id: \.self) { source in
                            sourceRow(source)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
            }
        }
        .confirmationDialog(
            "Forget everything from this meeting?",
            isPresented: Binding(
                get: { controller.pendingForget != nil },
                set: { if !$0 { controller.cancelForget() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) { controller.confirmForget() }
            Button("Cancel", role: .cancel) { controller.cancelForget() }
        } message: {
            Text("Its decisions and action items are removed from every page, and Zeus won't learn from it again.")
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: WikiSource) -> some View {
        switch source {
        case .meeting(let id):
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Button { controller.openMeetingSource(id) } label: {
                        Label("Meeting: \(controller.title(forMeeting: id))", systemImage: "arrow.up.forward.square")
                            .font(.system(size: 11)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.cloudPrimary)
                    .disabled(controller.meetingSourceIssue(id) != nil)
                    .accessibilityIdentifier("memory.source.\(id.uuidString)")
                    .accessibilityHint("Opens the saved source in Meetings. An active recording or notes session stays running.")
                    if let issue = controller.meetingSourceIssue(id) {
                        Text(issue).font(.system(size: 10)).foregroundStyle(Theme.cloudSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button("Forget this meeting") { controller.requestForget(id) }
                    .accessibilityLabel("Forget everything from \(controller.title(forMeeting: id))")
            }
        case .preference(let key):
            Text("Preference: \(key)").font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
        case .memory:
            Text("Something you asked Zeus to remember")
                .font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
        }
    }
}

private struct WikiRelatedPages: View {
    let controller: WikiController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Related pages")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Explore connections…") { controller.openGraph() }
                    .font(.system(size: 11))
                    .disabled(controller.settingsUnreadable)
                    .accessibilityIdentifier("memory.connections.open")
                    .accessibilityHint("Shows a graph and an accessible list of authored links and shared sources.")
            }
            let related = controller.relatedPages
            if related.isEmpty {
                Text("No linked pages or shared sources yet.")
                    .font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(related) { relation in
                            Button { controller.selectRelated(relation.pageID) } label: {
                                HStack(spacing: 8) {
                                    Label(relation.title, systemImage: "link").lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(connectionLabel(for: relation))
                                        .foregroundStyle(Theme.cloudSecondary)
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.cloudPrimary)
                            .help(evidence(for: relation))
                            .accessibilityHint(evidence(for: relation))
                            .accessibilityIdentifier("memory.related.\(relation.pageID)")
                        }
                    }
                }
                .frame(maxHeight: 72)
            }
            Text("Link a page with [[Page title]].")
                .font(.system(size: 10)).foregroundStyle(Theme.cloudSecondary)
        }
    }

    private func connectionLabel(for relation: WikiRelatedPage) -> String {
        switch relation.linkDirection {
        case .outgoing: return "Linked from this page"
        case .incoming: return "Links to this page"
        case .both: return "Linked both ways"
        case nil: return "\(relation.sharedSources.count) shared source\(relation.sharedSources.count == 1 ? "" : "s")"
        }
    }

    private func evidence(for relation: WikiRelatedPage) -> String {
        let names = relation.sharedSources.map { source in
            switch source {
            case .meeting(let id): return "Meeting: \(controller.title(forMeeting: id))"
            case .preference(let key): return "Preference: \(key)"
            case .memory: return "An explicitly remembered item"
            }
        }
        var explanation = relation.linkDirection == nil ? "" : connectionLabel(for: relation) + ". "
        if !names.isEmpty { explanation += "Shared sources: " + names.joined(separator: "; ") }
        return explanation
    }
}

private struct WikiActions: View {
    let controller: WikiController
    let page: WikiPage

    var body: some View {
        HStack(spacing: 8) {
            Button(page.pinned ? "Unpin" : "Pin") { controller.togglePin(page.id) }
                .accessibilityHint("Keeps this page at the top of the list.")
            if page.scope == .global {
                Button("Make personal") { controller.makePersonal() }
                    .accessibilityHint("Takes this page out of the global scope.")
            } else {
                Button("Promote to global…") { controller.beginPromotion() }
                    .disabled(controller.promotionOpen || page.needsReview)
                    .accessibilityHint(page.needsReview
                        ? "Unavailable until you review this page."
                        : "Checks the page for sensitive information first.")
            }
            Button("Export…") { controller.exportSelected() }
                .disabled(page.needsReview)
                .accessibilityHint(page.needsReview
                    ? "Unavailable until you review this page."
                    : "Saves this page as a Markdown file you choose.")
            Spacer(minLength: 0)
            Button("Delete", role: .destructive) { controller.confirmingDelete = true }
                .accessibilityHint("Deletes this page and stops learning from the meetings behind it.")
        }
        .confirmationDialog(
            "Delete this page?",
            isPresented: Binding(
                get: { controller.confirmingDelete },
                set: { controller.confirmingDelete = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { controller.confirmDelete() }
            Button("Cancel", role: .cancel) { controller.confirmingDelete = false }
        } message: {
            Text("“\(page.title)” is removed, and Zeus won't learn from the meetings behind it again.")
        }
    }
}

// MARK: Promotion

private struct WikiPromotionPanel: View {
    let controller: WikiController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sensitive information found")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ember)
                .accessibilityAddTraits(.isHeader)
            Text("A global page must not contain these. Remove them from the text above, or tick each one to say it is fine to share.")
                .font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.promotionItems) { finding in
                        Toggle(isOn: Binding(
                            get: { controller.promotionAcknowledged.contains(finding.acknowledgementKey) },
                            set: { controller.setAcknowledged(finding.acknowledgementKey, $0) }
                        )) {
                            Text("\(finding.kind.label): \(finding.redacted)")
                                .font(.system(size: 11)).foregroundStyle(Theme.cloudPrimary)
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("\(finding.kind.label): \(finding.redacted)")
                        .accessibilityHint("Tick to acknowledge this item.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
            HStack(spacing: 8) {
                Button("Promote with these acknowledged") { controller.confirmPromotion() }
                    .disabled(!controller.allFindingsAcknowledged)
                Button("Cancel") { controller.closePromotion() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.bubbleRadius).fill(Theme.ember.opacity(0.14)))
        .accessibilityElement(children: .contain)
    }
}
