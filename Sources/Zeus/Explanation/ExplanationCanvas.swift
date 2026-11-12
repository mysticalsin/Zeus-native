import AppKit
import SwiftUI
import ZeusCore

/// The caller supplies the current audio-clock presentation, not future model state.
/// This view owns no clock, capture device, network request, or animation timer.
@MainActor
struct ExplanationCanvas: View {
    let scene: ExplanationScene
    @Binding var selection: String?
    var captureContext: ExplanationCaptureContext? = nil
    var isInteractive = true
    /// The desktop card passes false and 0: it is click-through and sizes the diagram itself.
    var showsObjectList = true
    var minimumHeight: CGFloat = 220
    var registry: ExplanationRegistry = .empty
    var approvedImages: [String: NSImage] = [:]
    var snapshotImage: NSImage? = nil
    var onEdit: (ExplanationOperation) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var viewportID = UUID()

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let layout = ExplanationCanvasLayout(scene: scene, size: geometry.size,
                    registry: registry, captureContext: captureContext, viewportID: viewportID,
                    reduceMotion: reduceMotion)
                ExplanationCanvasArtwork(layout: layout, selectedID: selection, images: approvedImages, snapshotImage: snapshotImage)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .accessibilityHidden(true)
                .gesture(SpatialTapGesture().onEnded { value in
                    guard isInteractive else { return }
                    selection = layout.hitTest(value.location)
                    focused = true
                })
                .overlay(alignment: .topLeading) {
                    if !layout.isValid {
                        Text("This scene cannot be displayed safely.").font(.callout).padding()
                    } else if !layout.hiddenLabelIDs.isEmpty {
                        Text(showsObjectList ? "\(layout.hiddenLabelIDs.count) labels available in Objects" : "\(layout.hiddenLabelIDs.count) labels hidden for space")
                            .font(.caption).padding(8).background(.regularMaterial).allowsHitTesting(false)
                    }
                }
                .focusable(isInteractive)
                .focused($focused)
                .onMoveCommand { direction in
                    guard isInteractive, let id = selection,
                          let operation = layout.nudge(id: id, direction: direction) else { return }
                    onEdit(operation)
                }
                .onDeleteCommand {
                    guard isInteractive, let id = selection, layout.items.contains(where: { $0.object.id == id }) else { return }
                    onEdit(.remove(id: id))
                }
            }
            .frame(minHeight: minimumHeight)
            if showsObjectList {
                ExplanationObjectList(objects: visibleObjects, selection: $selection,
                                      isInteractive: isInteractive, onEdit: onEdit)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Explanation diagram")
    }

    private var visibleObjects: [ExplanationObject] {
        guard (try? ExplanationSceneReducer.validate(scene, registry: registry)) != nil else { return [] }
        return scene.objects.values.filter {
            $0.space == .canvas || ($0.space == .capture && captureContext?.isCurrent(captureID: $0.captureID) == true)
        }.sorted { $0.id < $1.id }
    }
}

/// Render-only surface for a pass-through owned overlay: no focus or gestures.
@MainActor
struct ExplanationCanvasArtwork: View {
    let layout: ExplanationCanvasLayout
    var selectedID: String? = nil
    var images: [String: NSImage] = [:]
    var snapshotImage: NSImage? = nil
    var body: some View {
        Canvas { context, _ in
            var drawing = context
            ExplanationCanvasPainter.draw(layout, context: &drawing, selectedID: selectedID, images: images, snapshotImage: snapshotImage)
        }.accessibilityHidden(true)
    }
}

/// App-issued overlay projection. Model data can neither create a display context
/// nor choose a native window transform. The context is checked again by layout.
struct ExplanationCaptureDrawingTransform {
    let captureID: UUID
    let affine: CGAffineTransform
    let clip: CGRect
    init?(context: ExplanationCaptureContext, affine: CGAffineTransform, clip: CGRect) {
        guard context.isCurrent(captureID: context.geometry.captureID),
              [affine.a, affine.b, affine.c, affine.d, affine.tx, affine.ty,
               clip.minX, clip.minY, clip.width, clip.height].allSatisfy({ $0.isFinite && abs($0) <= 10_000_000 }),
              abs(affine.a * affine.d - affine.b * affine.c) > 0.000000001,
              clip.width > 0, clip.height > 0 else { return nil }
        captureID = context.geometry.captureID; self.affine = affine; self.clip = clip
    }
}

/// A real, keyboard reachable alternative to the drawing's hit regions. The
/// controller receives finite edits; this list never invokes arbitrary actions.
@MainActor
struct ExplanationObjectList: View {
    let objects: [ExplanationObject]
    @Binding var selection: String?
    var isInteractive = true
    var onEdit: (ExplanationOperation) -> Void = { _ in }

    var body: some View {
        DisclosureGroup("Objects (\(objects.count))") {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(objects) { object in
                        HStack(alignment: .top, spacing: 8) {
                            Button { selection = object.id } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: selection == object.id ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(object.accessibleDescription).font(.callout)
                                        if let text = object.text, text != object.accessibleDescription {
                                            Text(text).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if object.geometry.kind == .chart || object.geometry.kind == .timeline {
                                            Text(zip(object.geometry.labels ?? [], object.geometry.values ?? [])
                                                .map { "\($0): \($1.formatted(.number.precision(.fractionLength(0...3))))" }
                                                .joined(separator: "; "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!isInteractive)
                            .accessibilityIdentifier("explanation.object.\(object.id)")
                            .accessibilityValue(selection == object.id ? "Selected" : "")
                            if isInteractive && selection == object.id {
                                Button { onEdit(.remove(id: object.id)) } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless).help("Remove \(object.accessibleDescription)")
                                .accessibilityLabel("Remove \(object.accessibleDescription)")
                            }
                        }.padding(6)
                    }
                }
            }.frame(maxHeight: 170)
        }
        .font(.caption.weight(.medium))
        .accessibilityIdentifier("explanation.objects")
    }
}

enum ExplanationRenderPalette {
    static func native(_ color: ExplanationColor) -> NSColor {
        switch color {
        case .ink: .labelColor
        case .secondary: .secondaryLabelColor
        case .white: .white
        case .blue: .systemBlue
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .purple: .systemPurple
        case .cyan: .systemCyan
        case .clear: .clear
        }
    }
    static func color(_ color: ExplanationColor) -> Color { Color(nsColor: native(color)) }
}

/// Pure geometric decisions are shared by drawing, hit testing and keyboard edits.
/// Native text measurement is done once per presentation/layout, outside drawing.
@MainActor
struct ExplanationCanvasLayout {
    struct Item {
        let object: ExplanationObject
        let transform: CGAffineTransform
        let parentTransform: CGAffineTransform
        let clip: CGRect
        let bounds: CGRect
        let path: Path
        let linePoints: [CGPoint]
        let reveal: Double
        let opacity: Double
        var label: CGRect?
    }
    let viewport: CGRect
    let canvasBounds: CGRect
    let isValid: Bool
    private(set) var captureImageTransform: CGAffineTransform? = nil
    private(set) var captureImageSize: CGSize? = nil
    private(set) var captureImageClip: CGRect? = nil
    private(set) var items: [Item] = []
    private(set) var hiddenLabelIDs: [String] = []

    init(scene: ExplanationScene, size: CGSize, registry: ExplanationRegistry = .empty,
         captureContext: ExplanationCaptureContext? = nil, viewportID: UUID = UUID(), reduceMotion _: Bool = false,
         captureTransform: ExplanationCaptureDrawingTransform? = nil) {
        viewport = CGRect(origin: .zero, size: size)
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
              (try? ExplanationSceneReducer.validate(scene, registry: registry)) != nil,
              let projection = try? ExplanationViewportTransform(id: viewportID, canvasSize: scene.canvasSize,
                viewport: .init(x: 0, y: 0, width: size.width, height: size.height)) else {
            canvasBounds = .zero; isValid = false
            captureImageTransform = nil; captureImageSize = nil; captureImageClip = nil
            return
        }
        isValid = true
        let canvas = CGAffineTransform(a: projection.scale, b: 0, c: 0, d: projection.scale,
                                      tx: projection.origin.x, ty: projection.origin.y)
        canvasBounds = CGRect(x: projection.origin.x, y: projection.origin.y,
            width: scene.canvasSize.width * projection.scale, height: scene.canvasSize.height * projection.scale)
        let capture = try? captureContext?.projection(canvasSize: scene.canvasSize,
            viewport: .init(x: 0, y: 0, width: size.width, height: size.height), viewportID: viewportID)
        let captureCurrent = captureContext?.isCurrent(captureID: scene.captureID) == true
        let captureAffine: CGAffineTransform? = {
            guard captureCurrent else { return nil }
            if let captureTransform, captureTransform.captureID == scene.captureID { return captureTransform.affine }
            guard let capture else { return nil }
            return .init(a: capture.scale, b: 0, c: 0, d: capture.scale, tx: capture.origin.x, ty: capture.origin.y)
        }()
        let captureClip: CGRect = {
            if let captureTransform, captureTransform.captureID == scene.captureID { return captureTransform.clip.intersection(viewport) }
            guard let capture, let image = captureContext?.geometry.imageSize else { return .zero }
            return CGRect(x: capture.origin.x, y: capture.origin.y, width: image.width * capture.scale,
                          height: image.height * capture.scale).intersection(viewport)
        }()
        captureImageTransform = captureAffine
        captureImageSize = captureAffine == nil ? nil : captureContext.map {
            CGSize(width: $0.geometry.imageSize.width, height: $0.geometry.imageSize.height)
        }
        captureImageClip = captureAffine == nil ? nil : captureClip
        var transforms: [String: CGAffineTransform] = [:]
        var parents: [String: CGAffineTransform] = [:]
        func transform(_ object: ExplanationObject) -> CGAffineTransform? {
            if let result = transforms[object.id] { return result }
            let base: CGAffineTransform
            if let parentID = object.parentID, let parent = scene.objects[parentID] {
                guard let value = transform(parent) else { return nil }
                base = value
            } else if object.space == .canvas {
                base = canvas
            } else if object.space == .capture, let captureAffine, scene.captureID == object.captureID {
                base = captureAffine
            } else { return nil }
            parents[object.id] = base
            let result = Self.compose(base, Self.affine(object.transform))
            transforms[object.id] = result
            return result
        }
        let sorted = scene.objects.values.sorted {
            $0.transform.position.z == $1.transform.position.z ? $0.id < $1.id : $0.transform.position.z < $1.transform.position.z
        }
        var boxes: [String: CGRect] = [:]
        for object in sorted where object.space != .world && object.geometry.kind != .connector {
            guard let affine = transform(object) else { continue }
            let path = Self.shape(object.geometry).applying(affine)
            let point = CGPoint.zero.applying(affine)
            boxes[object.id] = path.isEmpty ? CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2) : path.boundingRect
        }
        let children = Dictionary(grouping: sorted.filter { $0.parentID != nil }, by: { $0.parentID! })
        var resolvedGroups: Set<String> = []
        func groupBounds(_ object: ExplanationObject) -> CGRect? {
            guard object.geometry.kind == .group else { return boxes[object.id] }
            if resolvedGroups.contains(object.id) { return boxes[object.id] }
            resolvedGroups.insert(object.id)
            let members = (children[object.id] ?? []).compactMap(groupBounds)
            if let first = members.first { boxes[object.id] = members.dropFirst().reduce(first) { $0.union($1) } }
            return boxes[object.id]
        }
        for object in sorted where object.space != .world && object.geometry.kind == .group { _ = groupBounds(object) }
        for object in sorted where object.space != .world {
            guard let affine = transform(object), let parent = parents[object.id] else { continue }
            var line = (object.geometry.points ?? []).map { CGPoint(x: $0.x, y: $0.y).applying(affine) }
            if object.geometry.kind == .connector,
               let from = object.geometry.fromID.flatMap({ boxes[$0] }),
               let to = object.geometry.toID.flatMap({ boxes[$0] }) {
                line = [Self.edge(of: from, toward: CGPoint(x: to.midX, y: to.midY)),
                        Self.edge(of: to, toward: CGPoint(x: from.midX, y: from.midY))]
            }
            let shape = object.geometry.kind == .group ? Path(boxes[object.id] ?? .zero)
                : line.isEmpty ? Self.shape(object.geometry).applying(affine) : Self.polyline(line)
            let anchor = CGPoint.zero.applying(affine)
            let bounds = shape.isEmpty ? CGRect(x: anchor.x, y: anchor.y, width: 1, height: 1) : shape.boundingRect
            var opacity = object.style.opacity, cursor = object.parentID
            while let id = cursor, let ancestor = scene.objects[id] {
                opacity *= ancestor.style.opacity * ancestor.reveal
                cursor = ancestor.parentID
            }
            items.append(.init(object: object, transform: affine, parentTransform: parent,
                               clip: object.space == .capture ? captureClip : canvasBounds.intersection(viewport), bounds: bounds,
                               path: shape, linePoints: line, reveal: object.reveal, opacity: opacity))
        }
        var occupied: [CGRect] = []
        let subjects = items.filter { ![.label, .group].contains($0.object.geometry.kind) && $0.opacity > 0 }.map(\.bounds)
        for index in items.indices {
            let item = items[index]
            guard item.opacity > 0, item.reveal > 0, let text = item.object.text, !text.isEmpty,
                  ![.badge, .card].contains(item.object.geometry.kind) else { continue }
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            let measured = (text as NSString).boundingRect(with: CGSize(width: min(230, size.width - 16), height: 72),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            let labelSize = CGSize(width: min(max(24, ceil(measured.width) + 16), max(1, size.width - 16)),
                                   height: min(88, max(28, ceil(measured.height) + 12)))
            let b = item.bounds
            let candidates = [CGPoint(x: b.maxX + 10, y: b.midY - labelSize.height / 2),
                              CGPoint(x: b.minX - labelSize.width - 10, y: b.midY - labelSize.height / 2),
                              CGPoint(x: b.midX - labelSize.width / 2, y: b.minY - labelSize.height - 10),
                              CGPoint(x: b.midX - labelSize.width / 2, y: b.maxY + 10)]
            let rect = candidates.map { CGRect(origin: $0, size: labelSize) }.first { candidate in
                item.clip.insetBy(dx: 4, dy: 4).contains(candidate)
                    && !occupied.contains(where: { $0.insetBy(dx: -4, dy: -4).intersects(candidate) })
                    && !subjects.contains(where: { $0.intersects(candidate) })
            }
            if let rect { items[index].label = rect; occupied.append(rect) }
            else { hiddenLabelIDs.append(item.object.id) }
        }
    }

    func hitTest(_ point: CGPoint) -> String? {
        guard isValid, viewport.contains(point) else { return nil }
        return items.reversed().first { item in
            guard item.object.geometry.kind != .group, item.clip.contains(point), item.opacity > 0, item.reveal > 0 else { return false }
            if item.label?.contains(point) == true { return true }
            if !item.linePoints.isEmpty {
                return Self.polyline(Self.revealed(item.linePoints, fraction: item.reveal))
                    .strokedPath(.init(lineWidth: max(12, Self.strokeWidth(item) + 8))).contains(point)
            }
            return item.path.contains(point) || item.path.strokedPath(.init(lineWidth: 12)).contains(point)
        }?.object.id
    }

    func nudge(id: String, direction: MoveCommandDirection) -> ExplanationOperation? {
        guard let item = items.first(where: { $0.object.id == id }), item.object.geometry.kind != .connector else { return nil }
        let delta: CGPoint
        switch direction { case .left: delta = .init(x: -8, y: 0); case .right: delta = .init(x: 8, y: 0)
        case .up: delta = .init(x: 0, y: -8); case .down: delta = .init(x: 0, y: 8)
        @unknown default: return nil }
        let inverse = item.parentTransform.inverted()
        let origin = CGPoint.zero.applying(inverse), end = delta.applying(inverse)
        let position = item.object.transform.position
        let next = ExplanationVector3(x: position.x + end.x - origin.x, y: position.y + end.y - origin.y, z: position.z)
        guard next.x.isFinite, next.y.isFinite, abs(next.x) <= ExplanationLimits.coordinate,
              abs(next.y) <= ExplanationLimits.coordinate else { return nil }
        return .move(id: id, position: next)
    }

    static func affine(_ t: ExplanationTransform) -> CGAffineTransform {
        let cosine = cos(t.rotation.z), sine = sin(t.rotation.z)
        return .init(a: cosine * t.scale.x, b: sine * t.scale.x, c: -sine * t.scale.y,
                     d: cosine * t.scale.y, tx: t.position.x, ty: t.position.y)
    }
    static func strokeWidth(_ item: Item) -> CGFloat {
        min(256, max(0.5, item.object.style.lineWidth * sqrt(abs(item.transform.a * item.transform.d - item.transform.b * item.transform.c))))
    }
    static func compose(_ parent: CGAffineTransform, _ child: CGAffineTransform) -> CGAffineTransform {
        .init(a: parent.a * child.a + parent.c * child.b, b: parent.b * child.a + parent.d * child.b,
              c: parent.a * child.c + parent.c * child.d, d: parent.b * child.c + parent.d * child.d,
              tx: parent.a * child.tx + parent.c * child.ty + parent.tx,
              ty: parent.b * child.tx + parent.d * child.ty + parent.ty)
    }
    static func polyline(_ points: [CGPoint]) -> Path {
        var result = Path()
        if let first = points.first { result.move(to: first); for point in points.dropFirst() { result.addLine(to: point) } }
        return result
    }
    /// Unequal segments advance at constant distance, rather than one vertex per tick.
    static func revealed(_ points: [CGPoint], fraction: Double) -> [CGPoint] {
        guard fraction.isFinite, fraction > 0, let first = points.first else { return [] }
        if fraction >= 1 { return points }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = lengths.reduce(0, +) * fraction
        var result = [first]
        for (index, length) in lengths.enumerated() where length > 0 {
            let a = points[index], b = points[index + 1]
            if remaining >= length { result.append(b); remaining -= length }
            else {
                result.append(.init(x: a.x + (b.x - a.x) * remaining / length, y: a.y + (b.y - a.y) * remaining / length))
                break
            }
        }
        return result
    }
    static func edge(of rect: CGRect, toward point: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY), dx = point.x - rect.midX, dy = point.y - rect.midY
        guard abs(dx) + abs(dy) > 0.000001 else { return center }
        let factor = min(abs(dx) > 0 ? rect.width / 2 / abs(dx) : .infinity,
                         abs(dy) > 0 ? rect.height / 2 / abs(dy) : .infinity)
        return CGPoint(x: center.x + dx * factor, y: center.y + dy * factor)
    }
    static func shape(_ geometry: ExplanationGeometry) -> Path {
        if let points = geometry.points { return polyline(points.map { .init(x: $0.x, y: $0.y) }) }
        if let radius = geometry.radius, [.point, .ring, .badge].contains(geometry.kind) {
            return Path(ellipseIn: .init(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        }
        if let size = geometry.size {
            return Path(roundedRect: CGRect(x: 0, y: 0, width: size.x, height: size.y),
                        cornerRadius: min(geometry.radius ?? 8, min(size.x, size.y) / 2))
        }
        return Path()
    }
}

@MainActor
enum ExplanationCanvasPainter {
    static func draw(_ layout: ExplanationCanvasLayout, context: inout GraphicsContext,
                     selectedID: String?, images: [String: NSImage], snapshotImage: NSImage? = nil) {
        guard layout.isValid else { return }
        context.clip(to: Path(layout.viewport))
        if let snapshotImage, let transform = layout.captureImageTransform,
           let size = layout.captureImageSize, let clip = layout.captureImageClip {
            var background = context
            background.clip(to: Path(clip)); background.concatenate(transform)
            background.draw(Image(nsImage: snapshotImage), in: CGRect(origin: .zero, size: size))
        }
        for item in layout.items {
            var ctx = context
            ctx.clip(to: Path(item.clip))
            ctx.opacity = item.opacity
            let object = item.object, kind = object.geometry.kind
            let fill = ExplanationRenderPalette.color(object.style.fill)
            let stroke = ExplanationRenderPalette.color(object.style.stroke)
            let width = ExplanationCanvasLayout.strokeWidth(item)
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round,
                                   dash: object.style.dashed || kind == .region ? [6, 5] : [])
            if item.reveal <= 0 { continue }
            if !item.linePoints.isEmpty {
                let visible = ExplanationCanvasLayout.revealed(item.linePoints, fraction: item.reveal)
                ctx.stroke(ExplanationCanvasLayout.polyline(visible), with: .color(stroke), style: style)
                if kind == .arrow || kind == .connector, visible.count >= 2 {
                    let tip = visible[visible.count - 1], before = visible[visible.count - 2]
                    let angle = atan2(tip.y - before.y, tip.x - before.x)
                    let length = min(hypot(tip.x - before.x, tip.y - before.y), max(8, min(18, width * 3)))
                    var head = Path(); head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - length * cos(angle - 0.45), y: tip.y - length * sin(angle - 0.45)))
                    head.addLine(to: CGPoint(x: tip.x - length * cos(angle + 0.45), y: tip.y - length * sin(angle + 0.45)))
                    head.closeSubpath(); ctx.fill(head, with: .color(stroke))
                }
            } else if kind == .chart || kind == .timeline {
                drawData(item, context: &ctx)
            } else if kind == .image {
                if let id = object.assetID, let image = images[id], image.size.width > 0, image.size.height > 0,
                   image.size.width <= 4096, image.size.height <= 4096, let size = object.geometry.size {
                    var imageContext = ctx
                    imageContext.concatenate(item.transform)
                    imageContext.draw(Image(nsImage: image), in: CGRect(x: 0, y: 0, width: size.x, height: size.y))
                } else {
                    ctx.fill(item.path, with: .color(.secondary.opacity(0.1)))
                    ctx.draw(Text("Image unavailable").font(.caption), in: item.bounds.insetBy(dx: 4, dy: 4))
                }
            } else if kind != .label && kind != .group {
                if kind != .ring && kind != .region {
                    ctx.fill(item.path, with: .color(fill.opacity(kind == .highlight ? 0.24 : [.point, .badge].contains(kind) ? 0.85 : 0.14)))
                }
                ctx.stroke(item.path.trimmedPath(from: 0, to: item.reveal), with: .color(stroke), style: style)
                if [.card, .badge].contains(kind), let text = object.text {
                    ctx.draw(Text(text).font(.system(size: kind == .badge ? 12 : 14, weight: .medium))
                        .foregroundStyle(.primary), in: item.bounds.insetBy(dx: kind == .badge ? 2 : 10, dy: 4))
                }
            }
            if object.highlighted || object.id == selectedID {
                ctx.stroke(Path(roundedRect: item.bounds.insetBy(dx: -5, dy: -5), cornerRadius: 6),
                           with: .color(.accentColor), style: .init(lineWidth: 2, dash: object.id == selectedID ? [3, 3] : []))
            }
            if let label = item.label, let text = object.text {
                ctx.fill(Path(roundedRect: label, cornerRadius: 6), with: .color(Color(nsColor: .textBackgroundColor).opacity(0.95)))
                ctx.draw(Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary),
                         in: label.insetBy(dx: 8, dy: 6))
            }
        }
    }

    /// All data arithmetic is in `ExplanationChartMath`; this only chooses what to draw.
    private static func drawData(_ item: ExplanationCanvasLayout.Item, context: inout GraphicsContext) {
        let geometry = item.object.geometry
        guard let size = geometry.size else { return }
        let local = CGRect(x: 0, y: 0, width: size.x, height: size.y)
        var ctx = context
        ctx.concatenate(item.transform)
        ctx.clip(to: Path(CGRect(x: 0, y: 0, width: local.width * CGFloat(item.reveal), height: local.height)))
        let plan = ExplanationChartMath.plan(kind: geometry.kind, values: geometry.values ?? [],
                                             labels: geometry.labels ?? [], axis: geometry.axis)
        switch plan {
        case .rejected(let reason):
            ExplanationChartPainter.drawRefusal(reason, in: local, context: &ctx)
        case .plan(let value):
            ExplanationChartPainter.draw(value, in: local, color: ExplanationRenderPalette.color(item.object.style.fill), context: &ctx)
        }
    }
}
