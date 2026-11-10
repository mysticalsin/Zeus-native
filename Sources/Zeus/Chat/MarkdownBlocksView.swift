import AppKit
import SwiftUI
import ZeusCore

/// Renders `MarkdownBlock`s in ZEUS's dark style: headings, lists, task items, code blocks
/// with a copy button, quotes and rules. Inline Markdown (bold, `code`, links) inside each.
struct MarkdownBlocksView: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = Theme.cloudPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.55) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(.system(size: size + CGFloat(max(4 - level, 0)) * 1.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(Self.inline(text)).font(.system(size: size, design: .rounded)).foregroundStyle(color)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: size * 0.3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        marker(item, ordered: ordered)
                            .frame(minWidth: size, alignment: .trailing)
                        Text(Self.inline(item.text)).font(.system(size: size, design: .rounded)).foregroundStyle(color)
                            .strikethrough(item.checked == true, color: color.opacity(0.6))
                    }
                    .padding(.leading, CGFloat(item.depth) * size * 1.2)
                    .accessibilityElement(children: .combine)
                }
            }
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, size: size)
        case .quote(let text):
            HStack(spacing: 8) {
                Capsule().fill(Theme.cloudQuiet).frame(width: 3)
                Text(Self.inline(text)).font(.system(size: size, design: .rounded)).foregroundStyle(Theme.cloudSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func marker(_ item: MarkdownBlock.Item, ordered: Bool) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: size * 0.9)).foregroundStyle(checked ? Theme.leaf : Theme.cloudQuiet)
                .accessibilityLabel(checked ? "Done" : "Not done")
        } else if ordered, let number = item.number {
            Text("\(number).").font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.cloudSecondary)
        } else {
            Text(item.depth == 0 ? "•" : "◦").font(.system(size: size, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                .accessibilityHidden(true)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(.system(size: size * 0.78, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.cloudQuiet)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: size * 0.88, design: .monospaced))
                    .foregroundStyle(Theme.cloudPrimary)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(10)
            }
            .scrollIndicators(.never)
        }
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(TopBarStyle.tileStroke))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Code block\(language.map { ", \($0)" } ?? "")")
    }
}
