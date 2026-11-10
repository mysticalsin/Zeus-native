#!/usr/bin/env swift
import AppKit

let repo = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let src = repo.appendingPathComponent("Design/brand-logos-src")
let out = repo.appendingPathComponent("Sources/Zeus/Integrations/Brands")

let pairs: [(String, String)] = [
    ("cursor.svg", "engine-cursor.pdf"),
    ("openai.svg", "engine-openai.pdf"),
    ("claude.svg", "engine-claude.pdf"),
    ("anthropic.svg", "engine-anthropic.pdf"),
    ("googlegemini.svg", "engine-gemini.pdf"),
    ("kimi.svg", "engine-kimi.pdf"),
]

func exportPDF(image: NSImage, to url: URL) throws {
    image.size = NSSize(width: 24, height: 24)
    image.isTemplate = true
    let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    view.image = image
    view.imageScaling = .scaleProportionallyUpOrDown
    let data = view.dataWithPDF(inside: view.bounds)
    try data.write(to: url, options: .atomic)
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for (svg, pdf) in pairs {
    let input = src.appendingPathComponent(svg)
    guard let image = NSImage(contentsOf: input) else {
        fputs("missing or unreadable \(input.path)\n", stderr)
        exit(1)
    }
    try exportPDF(image: image, to: out.appendingPathComponent(pdf))
    print("wrote \(pdf)")
}

if let fallback = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil) {
    try exportPDF(image: fallback, to: out.appendingPathComponent("engine-fallback.pdf"))
    print("wrote engine-fallback.pdf")
} else {
    fputs("could not build fallback symbol\n", stderr)
    exit(1)
}
