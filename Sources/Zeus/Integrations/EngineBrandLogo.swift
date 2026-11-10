import AppKit
import SwiftUI
import ZeusCore

/// Loads each verified vector format from the bundled brand directory. Unsupported SVG
/// decoding returns nil so the views keep their existing safe text/symbol fallback.
enum EngineBrandImage {
    /// This deliberately excludes the source-tree fallback so native tests prove packaging.
    static func bundledURL(for mark: EngineBrandMark) -> URL? {
        Bundle.module.url(forResource: mark.assetName, withExtension: mark.assetExtension, subdirectory: "Brands")
    }

    static func url(for mark: EngineBrandMark) -> URL? {
        let name = "\(mark.assetName).\(mark.assetExtension)"
        let candidates = [
            bundledURL(for: mark),
            ZeusResources.bundle?.resourceURL?.appendingPathComponent("Brands/\(name)"),
            Bundle.main.resourceURL?.appendingPathComponent("Brands/\(name)"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Brands/\(name)"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func load(_ mark: EngineBrandMark) -> NSImage? {
        guard let url = url(for: mark), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// Engine logo for agent rows and integration lists. Drawn as a template in the primary label colour.
struct EngineBrandLogo: View {
    let agentLabel: String
    var size: CGFloat = 16

    private var mark: EngineBrandMark { EngineBrand.resolve(agentLabel) }

    var body: some View {
        Group {
            if let image = EngineBrandImage.load(mark) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.78, weight: .medium))
            }
        }
        .foregroundStyle(Theme.cloudPrimary)
        .frame(width: size, height: size)
        .accessibilityLabel(agentLabel)
        .help(agentLabel)
    }
}

/// Snapshot / debug: one agent list row per sample engine (light or dark).
struct EngineBrandRowSnapshot: View {
    let agents: [String]
    var dark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(agents, id: \.self) { agent in
                HStack(spacing: 8) {
                    Circle().fill(Theme.bolt).frame(width: 7, height: 7)
                    EngineBrandLogo(agentLabel: agent, size: 16)
                    Text("project · Running")
                        .font(TopBarStyle.label(10.5))
                        .foregroundStyle(Theme.cloudQuiet)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .frame(height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .frame(width: 270)
        .background(Theme.storm)
        .preferredColorScheme(dark ? .dark : .light)
    }
}

enum EngineBrandSnapshotExport {
    /// Writes light and dark agent-row PNGs at each scale; returns paths written.
    @MainActor
    static func writeRows(to directory: URL, scales: [CGFloat] = [2, 4]) throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        GlassFonts.register()
        TopBarStyle.isSnapshot = true
        defer { TopBarStyle.isSnapshot = false }
        let agents = EngineBrand.debugSampleAgents
        var paths: [String] = []
        for scale in scales {
            for (name, dark) in [("light", false), ("dark", true)] {
                let view = EngineBrandRowSnapshot(agents: agents, dark: dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = scale
                guard let cg = renderer.cgImage else { throw ExportError.renderFailed("\(name)@\(scale)x") }
                let suffix = scale == scale.rounded() ? "\(Int(scale))x" : "\(scale)x"
                let url = directory.appendingPathComponent("agent-logo-row-\(name)-\(suffix).png")
                let rep = NSBitmapImageRep(cgImage: cg)
                guard let data = rep.representation(using: .png, properties: [:]) else {
                    throw ExportError.encodeFailed("\(name)@\(scale)x")
                }
                try data.write(to: url, options: .atomic)
                paths.append(url.path)
            }
        }
        return paths
    }

    enum ExportError: Error {
        case renderFailed(String)
        case encodeFailed(String)
    }
}
