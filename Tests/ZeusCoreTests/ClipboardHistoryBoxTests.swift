import Foundation
import Testing
@testable import ZeusCore

@Suite("Clipboard history box")
struct ClipboardHistoryBoxTests {
    @Test func theLimitsStayAtTheHistoryCaps() {
        #expect(ClipboardHistoryBox.textLimit == 200_000)
        #expect(ClipboardHistoryBox.previewLimit == 120)
        #expect(ClipboardHistoryBox.fileNameLimit == 3)
    }

    @Test func textAddAcceptsARealCopyAndRejectsBlankOrHuge() {
        #expect(ClipboardHistoryBox.canAddText("hello"))
        #expect(ClipboardHistoryBox.canAddText("  a  "))
        #expect(!ClipboardHistoryBox.canAddText(""))
        #expect(!ClipboardHistoryBox.canAddText("   "))
        #expect(!ClipboardHistoryBox.canAddText("\n\t"))
        #expect(ClipboardHistoryBox.canAddText(String(repeating: "a", count: 200_000)))
        #expect(!ClipboardHistoryBox.canAddText(String(repeating: "a", count: 200_001)))
        #expect(!ClipboardHistoryBox.canAddText(String(repeating: " ", count: 200_000)))
    }

    @Test func anImageFileHasToBeNonempty() {
        #expect(ClipboardHistoryBox.canAddImage(file: "abc.png"))
        #expect(ClipboardHistoryBox.canAddImage(file: " "))
        #expect(!ClipboardHistoryBox.canAddImage(file: ""))
    }

    @Test func kindPrefersAnImageFileThenPathsThenALink() {
        #expect(ClipboardHistoryBox.kind(imageFile: "abc.png", filePaths: ["/tmp/a.pdf"], text: "https://a.com") == .image)
        #expect(ClipboardHistoryBox.kind(imageFile: "", filePaths: [], text: "hello") == .image)
        #expect(ClipboardHistoryBox.kind(imageFile: nil, filePaths: ["/tmp/a.pdf"], text: "https://a.com") == .file)
        #expect(ClipboardHistoryBox.kind(imageFile: nil, filePaths: [""], text: "hello") == .file)
        #expect(ClipboardHistoryBox.kind(imageFile: nil, filePaths: [], text: "https://a.com") == .link)
        #expect(ClipboardHistoryBox.kind(imageFile: nil, filePaths: [], text: "hello") == .text)
    }

    @Test func identityKeysKeepTheImageFileThePathsAndTheText() {
        #expect(ClipboardHistoryBox.identityKey(kind: .image, imageFile: "abc.png", filePaths: [], text: "Image") == "image:abc.png")
        #expect(ClipboardHistoryBox.identityKey(kind: .image, imageFile: nil, filePaths: [], text: "") == "image:")
        #expect(ClipboardHistoryBox.identityKey(kind: .file, imageFile: nil, filePaths: ["/tmp/a.pdf", "/tmp/b.png"], text: "a.pdf, b.png") == "file:/tmp/a.pdf\n/tmp/b.png")
        #expect(ClipboardHistoryBox.identityKey(kind: .link, imageFile: nil, filePaths: [], text: "https://a.com") == "text:https://a.com")
        #expect(ClipboardHistoryBox.identityKey(kind: .text, imageFile: nil, filePaths: [], text: "hello") == "text:hello")
    }

    @Test func previewFlattensLinesTrimsAndStopsAtOneHundredTwenty() {
        #expect(ClipboardHistoryBox.preview("hello") == "hello")
        #expect(ClipboardHistoryBox.preview("  hello\nworld  ") == "hello world")
        #expect(ClipboardHistoryBox.preview("a\n\nb") == "a b")
        #expect(ClipboardHistoryBox.preview("\n\n") == "")
        let exact = String(repeating: "a", count: 120)
        #expect(ClipboardHistoryBox.preview(exact) == exact)
        let over = String(repeating: "b", count: 121)
        #expect(ClipboardHistoryBox.preview(over) == String(repeating: "b", count: 119) + "…")
        #expect(ClipboardHistoryBox.preview(over).count == 120)
    }

    @Test func linksAreHTTPAndMailtoAfterTrim() {
        #expect(ClipboardHistoryBox.isLink("https://example.com/a"))
        #expect(ClipboardHistoryBox.isLink("  mailto:a@b.com\n"))
        #expect(ClipboardHistoryBox.isLink("HTTP://Example.com/A"))
        #expect(!ClipboardHistoryBox.isLink("plain words"))
        #expect(!ClipboardHistoryBox.isLink("ftp://files.example/a"))
        #expect(!ClipboardHistoryBox.isLink(""))
        #expect(!ClipboardHistoryBox.isLink("   "))
        #expect(!ClipboardHistoryBox.isLink("/tmp/shot.PNG"))
    }

    @Test func imageHintsAreTheCaptureSuffixes() {
        #expect(ClipboardHistoryBox.isImageHint("/tmp/shot.PNG"))
        #expect(ClipboardHistoryBox.isImageHint("a.jpg"))
        #expect(ClipboardHistoryBox.isImageHint("a.JPEG"))
        #expect(ClipboardHistoryBox.isImageHint("a.GIF"))
        #expect(ClipboardHistoryBox.isImageHint("a.webp"))
        #expect(ClipboardHistoryBox.isImageHint("a.heic"))
        #expect(!ClipboardHistoryBox.isImageHint("png is a word"))
        #expect(!ClipboardHistoryBox.isImageHint("a.png.bak"))
        #expect(!ClipboardHistoryBox.isImageHint("a.heif"))
        #expect(!ClipboardHistoryBox.isImageHint(""))
    }

    @Test func filtersSplitTextLinksImagesAndFiles() {
        #expect(ClipboardHistoryBox.includes(filter: .all, kind: .text, isImageHint: false))
        #expect(ClipboardHistoryBox.includes(filter: .all, kind: .file, isImageHint: false))
        #expect(ClipboardHistoryBox.includes(filter: .text, kind: .text, isImageHint: false))
        #expect(!ClipboardHistoryBox.includes(filter: .text, kind: .text, isImageHint: true))
        #expect(!ClipboardHistoryBox.includes(filter: .text, kind: .link, isImageHint: false))
        #expect(ClipboardHistoryBox.includes(filter: .links, kind: .link, isImageHint: false))
        #expect(!ClipboardHistoryBox.includes(filter: .links, kind: .text, isImageHint: false))
        #expect(ClipboardHistoryBox.includes(filter: .images, kind: .image, isImageHint: false))
        #expect(ClipboardHistoryBox.includes(filter: .images, kind: .text, isImageHint: true))
        #expect(!ClipboardHistoryBox.includes(filter: .images, kind: .text, isImageHint: false))
        #expect(!ClipboardHistoryBox.includes(filter: .images, kind: .link, isImageHint: false))
        #expect(ClipboardHistoryBox.includes(filter: .files, kind: .file, isImageHint: false))
        #expect(!ClipboardHistoryBox.includes(filter: .files, kind: .image, isImageHint: false))
    }

    @Test func imageLabelUsesTheTimesSign() {
        #expect(ClipboardHistoryBox.imageLabel(width: 10, height: 20) == "Image 10 \u{00D7} 20")
        #expect(ClipboardHistoryBox.imageLabel(width: 0, height: 0) == "Image 0 \u{00D7} 0")
        #expect(ClipboardHistoryBox.imageLabel(width: -1, height: 4) == "Image -1 \u{00D7} 4")
    }

    @Test func emptyPathsAreDroppedAndTheRestStayInOrder() {
        #expect(ClipboardHistoryBox.nonemptyPaths(["", "/tmp/a.pdf", "", "b.png"]) == ["/tmp/a.pdf", "b.png"])
        #expect(ClipboardHistoryBox.nonemptyPaths(["", ""]) == [])
        #expect(ClipboardHistoryBox.nonemptyPaths([]) == [])
    }

    @Test func fileLabelUsesTheLastComponentAndCapsAtThree() {
        #expect(ClipboardHistoryBox.fileLabel(["/tmp/a.pdf"]) == "a.pdf")
        #expect(ClipboardHistoryBox.fileLabel(["/tmp/a.pdf", "/var/b.png"]) == "a.pdf, b.png")
        #expect(ClipboardHistoryBox.fileLabel(["/tmp/dir/a.pdf", "b.png", "/c.txt"]) == "a.pdf, b.png, c.txt")
        #expect(ClipboardHistoryBox.fileLabel(["/tmp/a.pdf", "/var/b.png", "c.txt", "/d/e.gif"]) == "a.pdf, b.png, c.txt +1")
        #expect(ClipboardHistoryBox.fileLabel(["/tmp/a.pdf", "b.png", "c.txt", "d.txt", "e.txt"]) == "a.pdf, b.png, c.txt +2")
    }

    @Test func duplicateIndexFindsTheFirstMatch() {
        let keys = ["text:a", "text:b", "text:a"]
        #expect(ClipboardHistoryBox.duplicateIndex(keys: keys, key: "text:a") == 0)
        #expect(ClipboardHistoryBox.duplicateIndex(keys: keys, key: "text:b") == 1)
        #expect(ClipboardHistoryBox.duplicateIndex(keys: keys, key: "text:c") == nil)
        #expect(ClipboardHistoryBox.duplicateIndex(keys: [], key: "text:a") == nil)
    }

    @Test func trimIndexDropsTheLastUnpinnedRow() {
        #expect(ClipboardHistoryBox.trimIndex(count: 3, limit: 3, pinned: [false, false, true]) == nil)
        #expect(ClipboardHistoryBox.trimIndex(count: 2, limit: 1, pinned: [true, true]) == nil)
        #expect(ClipboardHistoryBox.trimIndex(count: 4, limit: 3, pinned: [false, false, true, false]) == 3)
        #expect(ClipboardHistoryBox.trimIndex(count: 4, limit: 3, pinned: [false, true, true, true]) == 0)
        #expect(ClipboardHistoryBox.trimIndex(count: 5, limit: 3, pinned: [false, false, false, true, false]) == 4)
        #expect(ClipboardHistoryBox.trimIndex(count: 1, limit: 0, pinned: [false]) == 0)
    }

    @Test func searchTrimsAndMatchesWithoutCase() {
        #expect(ClipboardHistoryBox.normalizedSearch("  Hello  ") == "Hello")
        #expect(ClipboardHistoryBox.normalizedSearch(" ") == "")
        #expect(ClipboardHistoryBox.normalizedSearch("") == "")
        #expect(ClipboardHistoryBox.matchesSearch(text: "Alpha", query: "  "))
        #expect(ClipboardHistoryBox.matchesSearch(text: "Alpha", query: ""))
        #expect(ClipboardHistoryBox.matchesSearch(text: "Alpha", query: "ALP"))
        #expect(ClipboardHistoryBox.matchesSearch(text: "Alpha", query: "pha"))
        #expect(!ClipboardHistoryBox.matchesSearch(text: "Alpha", query: "beta"))
        #expect(!ClipboardHistoryBox.matchesSearch(text: "Alpha", query: " alphabet "))
    }
}
