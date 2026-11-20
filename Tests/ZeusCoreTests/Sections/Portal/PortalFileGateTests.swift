import Foundation
import Testing
@testable import ZeusCore

@Suite("Portal file gate")
struct PortalFileGateTests {
    @Test func aPlainFileInsideTheInboxIsAdmitted() throws {
        let admitted = try #require(try PortalFileGate.decide(PortalFixtures.claim()).get())
        #expect(admitted.displayName == "note.txt")
        #expect(admitted.type == .plainText)
        #expect(admitted.outputKind == .utf8Text)
        #expect(admitted.sizeBytes == 4)
        #expect(admitted.path == "/sandbox/inbox/note.txt")
    }

    @Test func boundariesAndRejections() {
        let max = Int64(PortalLimits.maxConversionBytes)
        let cases: [(PortalFileClaim, PortalDropFailure?)] = [
            (PortalFixtures.claim(size: 0), .empty),
            (PortalFixtures.claim(size: 1), nil),
            (PortalFixtures.claim(size: max), nil),
            (PortalFixtures.claim(size: max + 1), .tooLarge),
            (PortalFixtures.claim(size: -1), .unreadableSize),
            (PortalFixtures.claim(path: ""), .emptyPath),
            (PortalFixtures.claim(path: "note.txt"), .notAbsolute),
            (PortalFixtures.claim(path: "/sandbox/inbox/../secret.txt"), .escapesSandbox),
            (PortalFixtures.claim(path: "/sandbox/inbox/./note.txt"), .escapesSandbox),
            (PortalFixtures.claim(path: "/sandbox/inbox//note.txt"), .escapesSandbox),
            (PortalFixtures.claim(path: "/sandbox/inbox-evil/note.txt"), .escapesSandbox),
            (PortalFixtures.claim(path: "/sandbox/inbox/note.txt\u{0}"), .escapesSandbox),
            (PortalFixtures.claim(path: "/sandbox/inbox/note\\txt"), .escapesSandbox),
            (PortalFixtures.claim(canonical: "/tmp/secret.txt"), .escapesSandbox),
            (PortalFixtures.claim(canonical: ""), .unresolved),
            (PortalFixtures.claim(symlink: true), .symlink),
            (PortalFixtures.claim(symlinkAncestor: true), .symlink),
            (PortalFixtures.claim(regular: false), .notRegularFile),
            (PortalFixtures.claim(links: 2), .hardLink),
            (PortalFixtures.claim(links: 0), .notRegularFile),
            (PortalFixtures.claim(owner: false), .wrongOwner),
            (PortalFixtures.claim(name: "run.exe", type: .unknown), .typeNotAllowed),
            (PortalFixtures.claim(name: "note.txt", type: .png), .typeMismatch),
            (PortalFixtures.claim(name: "photo.jpg", type: .jpeg), nil),
            (PortalFixtures.claim(name: ".secret.txt"), .unsafeName),
            (PortalFixtures.claim(name: "other.txt", path: "/sandbox/inbox/note.txt"), .unsafeName),
        ]
        for (claim, failure) in cases {
            let decision = PortalFileGate.decide(claim)
            if let failure {
                #expect(decision == .failure(failure))
            } else if case .success = decision {
            } else {
                Issue.record("expected admit for \(claim.displayName)")
            }
        }
    }

    @Test func extensionsMapOnlyTheDeclaredTypes() {
        #expect(PortalFileTypes.fromExtension("TXT") == .plainText)
        #expect(PortalFileTypes.fromExtension("text") == .plainText)
        #expect(PortalFileTypes.fromExtension("png") == .png)
        #expect(PortalFileTypes.fromExtension("JPG") == .jpeg)
        #expect(PortalFileTypes.fromExtension("jpeg") == .jpeg)
        #expect(PortalFileTypes.fromExtension("gif") == .gif)
        #expect(PortalFileTypes.fromExtension("tiff") == .tiff)
        #expect(PortalFileTypes.fromExtension("tif") == .tiff)
        #expect(PortalFileTypes.fromExtension("HEIC") == .heic)
        #expect(PortalFileTypes.fromExtension("heif") == .heic)
        #expect(PortalFileTypes.fromExtension("exe") == .unknown)
        #expect(PortalFileTypes.fromExtension("") == .unknown)
        #expect(PortalFileTypes.fromExtension("png.txt") == .plainText)
    }

    @Test func imageKindsBecomePngAndTextStaysText() throws {
        let photo = try #require(try PortalFileGate.decide(PortalFixtures.claim(name: "photo.heic", type: .heic)).get())
        #expect(photo.outputKind == .png)
        let text = try #require(try PortalFileGate.decide(PortalFixtures.claim()).get())
        #expect(text.outputKind == .utf8Text)
    }

    @Test func randomPathsStayInsideOrAreRefused() {
        var mixer = PortalSplitMix(state: 0x50_7A_11)
        let alphabet = Array("abcdefghij0123456789")
        for _ in 0..<160 {
            let count = 1 + mixer.int(4)
            var parts: [String] = []
            for _ in 0..<count {
                let length = 1 + mixer.int(6)
                parts.append(String((0..<length).map { _ in alphabet[mixer.int(alphabet.count)] }))
            }
            let name = parts.last! + ".txt"
            let head = parts.dropLast().joined(separator: "/")
            let path = head.isEmpty ? "/sandbox/inbox/\(name)" : "/sandbox/inbox/\(head)/\(name)"
            let claim = PortalFixtures.claim(name: name, path: path)
            if case .failure = PortalFileGate.decide(claim) { Issue.record("refused \(path)") }

            let escape = "/sandbox/inbox/" + parts.joined(separator: "/") + "/../secret.txt"
            #expect(PortalFileGate.decide(PortalFixtures.claim(name: "secret.txt", path: escape)) == .failure(.escapesSandbox))

            let sibling = "/sandbox/inbox" + parts[0] + "/note.txt"
            #expect(PortalFileGate.decide(PortalFixtures.claim(name: "note.txt", path: sibling)) == .failure(.escapesSandbox))
        }
    }

    @Test func pixelBoundsRejectOverflowAndTheExactCap() {
        #expect(PortalImageBounds.admit(width: 1, height: 1))
        #expect(PortalImageBounds.admit(width: PortalImageBounds.maxPixels, height: 1))
        #expect(!PortalImageBounds.admit(width: PortalImageBounds.maxPixels, height: 2))
        #expect(!PortalImageBounds.admit(width: 0, height: 1))
        #expect(!PortalImageBounds.admit(width: -1, height: 1))
        #expect(!PortalImageBounds.admit(width: Int.max, height: Int.max))
        #expect(PortalImageBounds.maxPixels == 16_000_000)
    }

    @Test func everyFailureHasItsOwnSentence() {
        let failures: [PortalDropFailure] = [
            .escapesSandbox, .notAbsolute, .emptyPath, .symlink, .notRegularFile, .hardLink,
            .wrongOwner, .unresolved, .empty, .tooLarge, .unreadableSize, .typeNotAllowed,
            .typeMismatch, .invalidContents, .sizeMismatch, .outputTooLarge, .systemCodecUnavailable,
            .trayFull, .outputEscapesSandbox, .unsafeName, .notAdmitted, .insecureSandbox, .writeFailed,
        ]
        var seen: Set<String> = []
        for failure in failures {
            let sentence = PortalCopy.sentence(failure)
            #expect(!sentence.isEmpty)
            #expect(seen.insert(sentence).inserted)
        }
        #expect(PortalCopy.sentence(.tooLarge) == "The file is larger than 8 MB.")
        #expect(PortalCopy.sentence(.symlink) == "Symbolic links are not converted.")
        #expect(PortalCopy.sentence(.systemCodecUnavailable) == "This Mac cannot convert that image locally.")
    }
}
