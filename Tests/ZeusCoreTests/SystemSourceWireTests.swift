import Foundation
import Testing
@testable import ZeusCore

@Suite("System source wire")
struct SystemSourceWireTests {
    @Test func decodesEveryLineShape() {
        #expect(SystemSourceLine.decode(json(#"{"t":"hello","v":1,"missing":2}"#))
            == .hello(version: 1, missing: 2))
        #expect(SystemSourceLine.decode(json(item(title: "Song"))) == .item(sampleItem(title: "Song")))
        #expect(SystemSourceLine.decode(json(#"{"t":"none","seq":4}"#)) == .none(sequence: 4))
        let jpeg = Data("hello".utf8)
        let encoded = jpeg.base64EncodedString()
        #expect(SystemSourceLine.decode(json(#"{"t":"art","key":"k","jpeg":"\#(encoded)"}"#))
            == .art(key: "k", jpeg: jpeg))
        #expect(SystemSourceLine.decode(json(#"{"t":"ack","id":7,"ok":false,"why":"stale"}"#))
            == .ack(id: 7, ok: false, why: .stale))
        #expect(SystemSourceLine.decode(json(#"{"t":"ack","id":8,"ok":true}"#))
            == .ack(id: 8, ok: true, why: nil))
        #expect(SystemSourceLine.decode(json(#"{"t":"pong","id":1,"extra":true}"#)) == .pong(id: 1))
        #expect(SystemSourceLine.decode(json(#"{"t":"read","id":2}"#)) == .read(id: 2))
        #expect(SystemSourceLine.decode(json(#"{"t":"ping","id":3}"#)) == .ping(id: 3))
    }

    @Test func encodesEveryCommandName() {
        let names: [SystemSourceCommand.Name] = [.play, .pause, .next, .previous, .seek]
        for name in names {
            let seconds = name == .seek ? 21.5 : 0
            let command = SystemSourceCommand(name: name, seconds: seconds, app: "com.apple.Music")
            #expect(SystemSourceLine.decode(command.line(id: 9))
                == .command(id: 9, command: command))
        }
    }

    @Test func clampsANegativeCommandBeforeItIsWritten() {
        let command = SystemSourceCommand(name: .pause, seconds: -4, app: "com.apple.Music")
        #expect(SystemSourceLine.decode(command.line(id: -2))
            == .command(id: 0, command: SystemSourceCommand(name: .pause, seconds: 0, app: "com.apple.Music")))
    }

    @Test func refusesALineOverOneMebibyteAndKeepsOneAtTheCap() {
        let body = #"{"t":"pong","id":1}"#
        let room = SystemSourceLine.maxBytes - body.utf8.count
        let exact = Data((body + String(repeating: " ", count: room)).utf8)
        #expect(exact.count == SystemSourceLine.maxBytes)
        #expect(SystemSourceLine.decode(exact) == .pong(id: 1))
        #expect(SystemSourceLine.decode(exact + Data([0x20])) == nil)
    }

    @Test func refusesBadJSONAndAnUnknownName() {
        for sample in ["{", "[]", "null", "\"hello\"", "", "{]", #"{"t":"pong","id":1}{"t":"read","id":2}"#] {
            #expect(SystemSourceLine.decode(json(sample)) == nil)
        }
        #expect(SystemSourceLine.decode(json(#"{"t":"quit","id":1}"#)) == nil)
        #expect(SystemSourceLine.decode(json(#"{"id":1}"#)) == nil)
        #expect(SystemSourceLine.decode(Data([0xff, 0xfe])) == nil)
    }

    @Test func refusesANonFiniteMeasureAndAWrongKind() {
        #expect(SystemSourceLine.decode(json(item(extra: #""elapsed":Infinity"#))) == nil)
        #expect(SystemSourceLine.decode(json(item(extra: #""rate":NaN"#))) == nil)
        #expect(SystemSourceLine.decode(json(item(extra: #""playing":1"#))) == nil)
        #expect(SystemSourceLine.decode(json(item(extra: #""seq":1.5"#))) == nil)
        #expect(SystemSourceLine.decode(json(#"{"t":"hello","v":2,"missing":0}"#)) == nil)
        #expect(SystemSourceLine.decode(json(#"{"t":"cmd","id":1,"name":"stop","seconds":0,"app":"com.apple.Music"}"#)) == nil)
        #expect(SystemSourceLine.decode(json(#"{"t":"ack","id":1,"ok":false,"why":"later"}"#)) == nil)
    }

    @Test func turnsNegativeNumbersIntoZero() {
        #expect(SystemSourceLine.decode(json(item(extra: #""elapsed":-3,"rate":-1,"at":-8,"seq":-4"#)))
            == .item(sampleItem(sequence: 0, elapsed: 0, at: 0, rate: 0)))
        #expect(SystemSourceLine.decode(json(#"{"t":"hello","v":1,"missing":-6}"#))
            == .hello(version: 1, missing: 0))
        #expect(SystemSourceLine.decode(json(#"{"t":"pong","id":-9}"#)) == .pong(id: 0))
    }

    @Test func missingOrNonFiniteDurationIsZero() {
        #expect(SystemSourceLine.decode(json(item(drop: "duration"))) == .item(sampleItem(duration: 0)))
        #expect(SystemSourceLine.decode(json(item(extra: #""duration":Infinity"#))) == .item(sampleItem(duration: 0)))
        #expect(SystemSourceLine.decode(json(item(extra: #""duration":-Infinity"#))) == .item(sampleItem(duration: 0)))
        #expect(SystemSourceLine.decode(json(item(extra: #""duration":-2"#))) == .item(sampleItem(duration: 0)))
        #expect(SystemSourceLine.decode(json(item(extra: #""duration":"long""#))) == nil)
    }

    @Test func cleansTitleText() {
        let override = "A\u{202E}B\nC"
        #expect(SystemSourceText.clean(override) == "AB C")
        #expect(SystemSourceLine.decode(json(item(title: override))) == .item(sampleItem(title: "AB C")))
        let long = String(repeating: "a", count: 300)
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(family.count == 1)
        #expect(SystemSourceText.clean(long + family) == long)
        #expect(SystemSourceText.clean(String(repeating: "a", count: 299) + family) == String(repeating: "a", count: 299) + family)
        #expect(SystemSourceText.clean("Go\u{0007}\t") == "Go")
    }

    @Test func dropsABadBundleIdentifierOrAMissingTitle() {
        #expect(SystemSourceLine.decode(json(item(app: "not a bundle"))) == nil)
        #expect(SystemSourceLine.decode(json(item(app: String(repeating: "a", count: 156)))) == nil)
        #expect(SystemSourceLine.decode(json(item(app: "com.apple.Music_2"))) == nil)
        #expect(SystemSourceLine.decode(json(item(drop: "title"))) == nil)
        #expect(SystemSourceLine.decode(json(item(title: "\u{202E}\u{0007}"))) == nil)
        #expect(SystemSourceLine.decode(json(item(title: "Infinity", extra: #""duration":Infinity"#)))
            == .item(sampleItem(title: "Infinity", duration: 0)))
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func item(title: String = "Song", app: String = "com.apple.Music", extra: String? = nil, drop: String? = nil) -> String {
        var fields = [
            "t": quoted("item"),
            "seq": "1",
            "app": quoted(app),
            "parent": quoted("com.apple.dock"),
            "title": quoted(title),
            "artist": quoted("Ada"),
            "album": quoted("Notes"),
            "duration": "12.5",
            "elapsed": "1",
            "at": "10",
            "rate": "1",
            "playing": "true",
            "key": quoted("k1"),
        ]
        if let drop { fields.removeValue(forKey: drop) }
        if let extra {
            for piece in extra.split(separator: ",") {
                guard let name = piece.split(separator: ":").first else { continue }
                fields.removeValue(forKey: String(name).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
        }
        var body = fields.map { "\"\($0.key)\":\($0.value)" }.sorted().joined(separator: ",")
        if let extra { body += "," + extra }
        return "{\(body)}"
    }

    private func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func sampleItem(title: String = "Song", sequence: Int = 1, duration: Double = 12.5,
                            elapsed: Double = 1, at: Double = 10, rate: Double = 1) -> SystemSourceItem {
        SystemSourceItem(sequence: sequence, app: "com.apple.Music", parent: "com.apple.dock", title: title,
                         artist: "Ada", album: "Notes", duration: duration, elapsed: elapsed, at: at, rate: rate,
                         playing: true, key: "k1")
    }
}
