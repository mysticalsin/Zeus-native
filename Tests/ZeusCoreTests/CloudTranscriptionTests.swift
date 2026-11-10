import Foundation
import Testing
@testable import ZeusCore

@Suite("Cloud transcription")
struct CloudTranscriptionTests {
    // MARK: Audio encoding

    @Test func pcm16IsLittleEndianAndClamped() {
        let data = PCM16.encode([0, 1, -1, 2, .nan])
        #expect(data.count == 10)
        let values = stride(from: 0, to: data.count, by: 2).map { Int16(littleEndian: data.subdata(in: $0..<$0 + 2).withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }) }
        #expect(values == [0, Int16.max, -Int16.max, Int16.max, 0])
    }

    @Test func wavHeaderDescribes16kMono16Bit() {
        let wav = PCM16.wav([Float](repeating: 0, count: 16_000))
        #expect(wav.count == 44 + 32_000)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav.subdata(in: 8..<16), as: UTF8.self) == "WAVEfmt ")
        func u32(_ offset: Int) -> UInt32 { UInt32(littleEndian: wav.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) }
        func u16(_ offset: Int) -> UInt16 { UInt16(littleEndian: wav.subdata(in: offset..<offset + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }) }
        #expect(u16(20) == 1 && u16(22) == 1)        // PCM, mono
        #expect(u32(24) == 16_000 && u32(28) == 32_000)
        #expect(u16(34) == 16)
        #expect(u32(40) == 32_000)
    }

    // MARK: OpenAI

    @Test func openAIRequestIsMultipartLikeTheDocs() throws {
        let request = OpenAITranscription.request(wav: Data("RIFFxxxx".utf8), apiKey: "sk-test", prompt: "Names: Zeus, Laya.",
                                                  keywords: ["Zeus", "Laya", "bad<term>"], language: "fr-FR", boundary: "B")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        #expect(body.contains("name=\"prompt\"\r\n\r\nNames: Zeus, Laya.\r\n"))
        #expect(body.contains("name=\"keywords[]\"\r\n\r\nZeus\r\n"))
        #expect(body.contains("name=\"keywords[]\"\r\n\r\nLaya\r\n"))
        #expect(!body.contains("bad<term>"))
        #expect(body.contains("name=\"languages[]\"\r\n\r\nfr\r\n"))
        #expect(!body.contains("name=\"language\""))
        #expect(body.contains("name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFFxxxx\r\n"))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test func openAIAutomaticLanguageSendsNoLanguages() throws {
        let request = OpenAITranscription.request(wav: Data(), apiKey: "k", prompt: "", keywords: [], language: nil, boundary: "B")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains("languages[]") && !body.contains("name=\"prompt\""))
    }

    @Test func openAIResponsesParse() throws {
        let ok = #"{"text": "Bonjour, pouvez-vous m'entendre ?", "languages": [{"code": "fr"}]}"#
        #expect(try OpenAITranscription.parse(data: Data(ok.utf8), status: 200) == "Bonjour, pouvez-vous m'entendre ?")
        #expect(throws: CloudTranscriptionError.rejectedKey("OpenAI")) {
            try OpenAITranscription.parse(data: Data(#"{"error":{"message":"Incorrect API key provided: sk-...abcd"}}"#.utf8), status: 401)
        }
        #expect(throws: CloudTranscriptionError.quota("OpenAI")) { try OpenAITranscription.parse(data: Data(), status: 429) }
        #expect(throws: CloudTranscriptionError.server("OpenAI", "Invalid file format.")) {
            try OpenAITranscription.parse(data: Data(#"{"error":{"message":"Invalid file format.\nSupported formats: wav"}}"#.utf8), status: 400)
        }
    }

    @Test func errorsAreOneLineAndNeverHoldTheKey() {
        let errors: [CloudTranscriptionError] = [.missingKey("OpenAI"), .rejectedKey("ElevenLabs"), .quota("OpenAI"),
                                                 .server("OpenAI", "x"), .network("ElevenLabs"), .timeout("OpenAI")]
        for error in errors {
            let text = error.errorDescription ?? ""
            #expect(!text.isEmpty && !text.contains("\n"))
        }
        #expect(CloudTranscriptionError.oneLine(String(repeating: "a", count: 300)).count == 140)
    }

    // MARK: ElevenLabs

    @Test func elevenLabsURLCarriesTheSessionSettings() throws {
        let url = ElevenLabsRealtime.url(language: "pt-BR", keyterms: ["Zeus", "Murmure", "x>y"])
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "wss" && components.host == "api.elevenlabs.io" && components.path == "/v1/speech-to-text/realtime")
        let items = components.queryItems ?? []
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }
        #expect(values("model_id") == ["scribe_v2_realtime"])
        #expect(values("audio_format") == ["pcm_16000"])
        #expect(values("commit_strategy") == ["manual"])
        #expect(values("language_code") == ["pt"])
        #expect(values("keyterms") == ["Zeus", "Murmure"])
        let automatic = ElevenLabsRealtime.url(language: nil, keyterms: [])
        #expect(!automatic.absoluteString.contains("language_code"))
    }

    @Test func elevenLabsAuthUsesTheHeaderNotTheURL() {
        let url = ElevenLabsRealtime.url(language: nil, keyterms: [])
        let request = ElevenLabsRealtime.request(url: url, apiKey: "xi-secret")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "xi-secret")
        #expect(!(request.url?.absoluteString.contains("xi-secret") ?? true))
    }

    @Test func elevenLabsAudioChunksMatchTheDocs() throws {
        let chunk = ElevenLabsRealtime.audioChunk(Data([1, 2, 3]), commit: false)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(chunk.utf8)) as? [String: Any])
        #expect(object["message_type"] as? String == "input_audio_chunk")
        #expect(object["audio_base_64"] as? String == "AQID")
        #expect(object["commit"] as? Bool == false)
        #expect(object["sample_rate"] as? Int == 16_000)

        let commit = try #require(try JSONSerialization.jsonObject(with: Data(ElevenLabsRealtime.audioChunk(Data(), commit: true).utf8)) as? [String: Any])
        #expect(commit["audio_base_64"] as? String == "" && commit["commit"] as? Bool == true)
        #expect(ElevenLabsRealtime.chunkBytes == 8_000)
    }

    @Test func elevenLabsServerMessagesParse() {
        let started = #"{"message_type":"session_started","session_id":"s1","config":{"sample_rate":16000,"audio_format":"pcm_16000","model_id":"scribe_v2_realtime"}}"#
        #expect(ElevenLabsRealtime.parse(started) == .started(sessionID: "s1"))
        #expect(ElevenLabsRealtime.parse(#"{"message_type":"partial_transcript","text":"hello ze"}"#) == .partial("hello ze"))
        #expect(ElevenLabsRealtime.parse(#"{"message_type":"committed_transcript","text":"Hello Zeus."}"#) == .committed("Hello Zeus."))
        #expect(ElevenLabsRealtime.parse(#"{"message_type":"committed_transcript_with_timestamps","text":"Hi.","language_code":"en","words":[]}"#) == .committed("Hi."))
        #expect(ElevenLabsRealtime.parse(#"{"message_type":"auth_error","error":"Invalid API key"}"#) == .failure(type: "auth_error", message: "Invalid API key"))
        #expect(ElevenLabsRealtime.parse(#"{"message_type":"warning","warning":"slow"}"#) == .warning("slow"))
        #expect(ElevenLabsRealtime.parse("not json") == .other("unreadable"))
    }

    @Test func elevenLabsErrorsMapToOneLiners() {
        #expect(ElevenLabsRealtime.error(type: "auth_error", message: "Invalid API key") == .rejectedKey("ElevenLabs"))
        #expect(ElevenLabsRealtime.error(type: "quota_exceeded", message: "q") == .quota("ElevenLabs"))
        #expect(ElevenLabsRealtime.error(type: "transcriber_error", message: "boom\ntrace") == .server("ElevenLabs", "boom"))
    }

    @Test func realtimeTranscriptJoinsCommittedSegmentsThenThePartial() {
        var transcript = RealtimeTranscript()
        transcript.apply(.partial("hello"))
        #expect(transcript.text == "hello")
        transcript.apply(.committed("Hello Zeus."))
        transcript.apply(.partial("open the"))
        #expect(transcript.text == "Hello Zeus. open the")
        transcript.apply(.committed("Open the notes."))
        #expect(transcript.text == "Hello Zeus. Open the notes.")
        #expect(transcript.committed.count == 2)
    }
}
