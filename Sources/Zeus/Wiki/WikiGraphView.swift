import SwiftUI
import ZeusCore

/// A focus graph and an equivalent list, both projected from the existing evidenced relationships.
/// The graph draws at most eight neighbors; the list keeps every matching result reachable.
struct WikiGraphView: View {
    let controller: WikiController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = controller.graphSnapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connections").font(.title2.weight(.semibold))
                    Text(controller.selectedPage?.title ?? "Select a Memory page")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("View", selection: Binding(get: { controller.graphShowsList }, set: { controller.graphShowsList = $0 })) {
                    Text("Graph").tag(false)
                    Text("List").tag(true)
                }.pickerStyle(.segmented).frame(width: 150)
            }
            HStack {
                TextField("Filter connected pages", text: Binding(get: { controller.graphQuery }, set: { controller.graphQuery = $0 }))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Filter connected pages")
                Picker("Connection type", selection: Binding(get: { controller.graphFilter }, set: { controller.graphFilter = $0 })) {
                    ForEach(WikiGraphFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }.frame(width: 190)
            }
            if controller.settingsUnreadable {
                Text("Connections are unavailable until Memory's settings are recovered.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                Group {
                    if controller.graphShowsList {
                        connectionList(snapshot)
                    } else {
                        WikiGraphCanvas(snapshot: snapshot, selectedRelationID: controller.graphRelationID,
                            openPage: { controller.selectGraphPage($0) }, inspect: { controller.graphRelationID = $0 })
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 270, maxHeight: 270)
                .transition(reduceMotion ? .identity : .opacity)
                .animation(Motion.feedback(reduceMotion: reduceMotion), value: controller.graphShowsList)

                if snapshot.relationships.isEmpty {
                    Text(snapshot.totalRelationshipCount == 0
                         ? "No authored links or shared sources yet. Connect pages by adding [[Page title]] to an edited page."
                         : "No connections match these filters. Clear the search or choose All connections.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Solid: authored link · Dashed: shared source").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !controller.graphShowsList && snapshot.hiddenCount > 0 {
                            Button("\(snapshot.hiddenCount) more in List") { controller.graphShowsList = true }.font(.caption)
                        } else {
                            Text("\(snapshot.relationships.count) connection\(snapshot.relationships.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let relation = snapshot.relationships.first(where: { $0.pageID == controller.graphRelationID }) {
                    WikiGraphEvidence(controller: controller, relation: relation)
                } else {
                    Text("Select a page to explore its connections. Select ⓘ to inspect the link or source evidence.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
                }
            }
            HStack {
                Text("Connections describe links and shared records, not agreement or causation.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { controller.graphOpen = false }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 660, height: 560)
        .background(Theme.storm).preferredColorScheme(.dark)
    }

    private func connectionList(_ snapshot: WikiGraphSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.relationships) { relation in
                    HStack(spacing: 10) {
                        Button { controller.selectGraphPage(relation.pageID) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(relation.title).font(.body.weight(.medium)).lineLimit(2)
                                Text(WikiGraphLabels.summary(relation)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityHint("Opens this Memory page and focuses its connections.")
                        Button { controller.graphRelationID = relation.pageID } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("Connection details for \(relation.title)")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                }
            }
        }.accessibilityLabel("Connected Memory pages")
    }
}

private struct WikiGraphCanvas: View {
    let snapshot: WikiGraphSnapshot
    let selectedRelationID: String?
    let openPage: (String) -> Void
    let inspect: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let nodeWidth = min(116.0, width * 0.2)
            ZStack {
                Canvas { context, size in
                    for edge in snapshot.edges {
                        guard let from = snapshot.nodes.first(where: { $0.id == edge.sourceID }),
                              let to = snapshot.nodes.first(where: { $0.id == edge.targetID }) else { continue }
                        let start = CGPoint(x: from.x * size.width, y: from.y * size.height)
                        let end = CGPoint(x: to.x * size.width, y: to.y * size.height)
                        let tint = edge.linkDirection == nil ? Theme.sky : Theme.accent
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        context.stroke(path, with: .color(tint.opacity(0.65)),
                            style: StrokeStyle(lineWidth: edge.targetID == selectedRelationID ? 2.2 : 1.2,
                                               dash: edge.linkDirection == nil ? [4, 4] : []))
                        if edge.linkDirection == .outgoing || edge.linkDirection == .both {
                            context.fill(Self.arrow(from: start, to: end, fraction: 0.74), with: .color(tint))
                        }
                        if edge.linkDirection == .incoming || edge.linkDirection == .both {
                            context.fill(Self.arrow(from: end, to: start, fraction: 0.74), with: .color(tint))
                        }
                    }
                }.accessibilityHidden(true)

                ForEach(snapshot.nodes) { node in
                    Group {
                        if node.isFocus {
                            nodeLabel(node, width: nodeWidth)
                                .accessibilityLabel("Current page: \(node.title)")
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Button { openPage(node.id) } label: { nodeLabel(node, width: nodeWidth) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(node.title)
                                .accessibilityHint("Opens this Memory page and focuses its connections.")
                                .help(node.title)
                        }
                    }.position(x: node.x * width, y: node.y * height)
                }
                ForEach(snapshot.edges) { edge in
                    if let node = snapshot.nodes.first(where: { $0.id == edge.targetID }),
                       let relation = snapshot.relationships.first(where: { $0.pageID == edge.targetID }) {
                        Button { inspect(edge.targetID) } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14)).foregroundStyle(Theme.cloudPrimary)
                                .padding(5).background(Circle().fill(Theme.storm))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Connection details for \(node.title)")
                        .accessibilityHint(WikiGraphLabels.summary(relation))
                        .help(WikiGraphLabels.summary(relation))
                        .position(x: (0.5 + node.x) * width / 2, y: (0.5 + node.y) * height / 2)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory connections graph")
    }

    private func nodeLabel(_ node: WikiGraphNode, width: Double) -> some View {
        Text(node.title).font(.system(size: 11, weight: node.isFocus ? .semibold : .medium))
            .lineLimit(2).multilineTextAlignment(.center)
            .frame(width: width, height: 42)
            .background(RoundedRectangle(cornerRadius: 9).fill(node.isFocus ? Theme.accentDeep : Theme.storm))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(node.isFocus ? Theme.accent : Color.white.opacity(0.25), lineWidth: 1))
            .foregroundStyle(Theme.cloudPrimary)
    }

    private static func arrow(from start: CGPoint, to end: CGPoint, fraction: Double) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x - 7 * cos(angle - 0.45), y: point.y - 7 * sin(angle - 0.45)))
        path.addLine(to: CGPoint(x: point.x - 7 * cos(angle + 0.45), y: point.y - 7 * sin(angle + 0.45)))
        path.closeSubpath()
        return path
    }
}

private struct WikiGraphEvidence: View {
    let controller: WikiController
    let relation: WikiRelatedPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("Why these pages connect").font(.caption.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(relation.title + " · " + WikiGraphLabels.summary(relation)).font(.caption)
                ForEach(relation.sharedSources, id: \.self) { source in
                    switch source {
                    case .meeting(let id):
                        Button {
                            controller.graphOpen = false
                            controller.openMeetingSource(id)
                        } label: {
                            Label(controller.title(forMeeting: id), systemImage: "arrow.up.forward.square").font(.caption)
                        }
                        .disabled(controller.meetingSourceIssue(id) != nil)
                        .accessibilityHint("Opens this shared source in Meetings. An active recording stays running.")
                    case .preference(let key):
                        Text("Shared preference: \(key)").font(.caption)
                    case .memory(let id):
                        Text("Shared remembered item: \(id.uuidString)").font(.caption).textSelection(.enabled)
                    }
                }
                if relation.sharedSources.isEmpty {
                    Text("This is an authored page link; no shared source record is asserted.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 68)
    }
}

private enum WikiGraphLabels {
    static func summary(_ relation: WikiRelatedPage) -> String {
        let link: String
        switch relation.linkDirection {
        case .outgoing: link = "Linked from the current page"
        case .incoming: link = "Links to the current page"
        case .both: link = "Authored links in both directions"
        case nil: link = ""
        }
        let shared = relation.sharedSources.isEmpty ? "" : "\(relation.sharedSources.count) shared source\(relation.sharedSources.count == 1 ? "" : "s")"
        return [link, shared].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
