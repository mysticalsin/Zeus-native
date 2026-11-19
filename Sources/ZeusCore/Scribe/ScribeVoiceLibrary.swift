import Foundation

// Voices the owner chose to remember. A voice is biometric data, so the rules are strict: a voice is saved only
// after the owner names a speaker and ticks "Remember this voice" (off by default); it lives in one file under
// Application Support/Zeus/Voices (0600, never in the vault, never uploaded); Settings lists every voice with
// Delete and Delete all, and a delete removes the entry from the file at once. Audio is never part of it.

public struct ScribeSavedVoice: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ScribeEmbeddingKind
    /// The mean embedding of the turns this voice was saved from.
    public var centroid: [Float]
    /// How many turns the centroid is the mean of.
    public var sampleCount: Int
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, kind: ScribeEmbeddingKind, centroid: [Float], sampleCount: Int, updatedAt: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.centroid = centroid
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
    }

    public var embedding: ScribeVoiceEmbedding { ScribeVoiceEmbedding(kind: kind, vector: centroid) }
}

public struct ScribeVoiceLibrary: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// A person's centroid stops moving much after this many turns, so an old voice cannot be dragged away by one
    /// odd meeting.
    public static let sampleCap = 40

    public var version = ScribeVoiceLibrary.currentVersion
    public private(set) var voices: [ScribeSavedVoice] = []

    public init(voices: [ScribeSavedVoice] = []) {
        self.voices = voices
    }

    public var isEmpty: Bool { voices.isEmpty }

    /// Saves the voice under `name`, or folds it into the voice already saved under that name (any capitalisation)
    /// and kind. Blank names and empty embeddings are refused.
    @discardableResult
    public mutating func remember(
        name: String, embedding: ScribeVoiceEmbedding, sampleCount: Int, now: Date = Date()
    ) -> ScribeSavedVoice? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !embedding.vector.isEmpty, sampleCount > 0 else { return nil }
        let wanted = ScribeSpeakerNames.key(trimmed)
        if let index = voices.firstIndex(where: { $0.kind == embedding.kind && ScribeSpeakerNames.key($0.name) == wanted }),
           voices[index].centroid.count == embedding.vector.count {
            let old = Float(voices[index].sampleCount)
            let new = Float(sampleCount)
            for position in voices[index].centroid.indices {
                voices[index].centroid[position] = (voices[index].centroid[position] * old + embedding.vector[position] * new) / (old + new)
            }
            voices[index].sampleCount = min(Self.sampleCap, voices[index].sampleCount + sampleCount)
            voices[index].updatedAt = now
            return voices[index]
        }
        let voice = ScribeSavedVoice(
            name: trimmed, kind: embedding.kind, centroid: embedding.vector,
            sampleCount: min(Self.sampleCap, sampleCount), updatedAt: now
        )
        voices.append(voice)
        return voice
    }

    /// The saved voice nearest to `embedding` and within the threshold for its kind, if any.
    public func match(_ embedding: ScribeVoiceEmbedding, threshold: Float? = nil) -> ScribeSavedVoice? {
        let limit = threshold ?? ScribeVoiceEmbedding.defaultThreshold(for: embedding.kind)
        var best: (voice: ScribeSavedVoice, distance: Float)?
        for voice in voices where voice.kind == embedding.kind {
            let distance = voice.embedding.distance(to: embedding)
            if best == nil || distance < best!.distance { best = (voice, distance) }
        }
        guard let best, best.distance <= limit else { return nil }
        return best.voice
    }

    /// The saved voices of one kind, as the name and embedding the diarizer is seeded with.
    public func seeds(kind: ScribeEmbeddingKind) -> [(name: String, embedding: ScribeVoiceEmbedding)] {
        voices.filter { $0.kind == kind }.map { ($0.name, $0.embedding) }
    }

    public var names: [String] { voices.map(\.name) }

    public mutating func delete(id: UUID) {
        voices.removeAll { $0.id == id }
    }

    public mutating func deleteAll() {
        voices.removeAll()
    }
}

public enum ScribeVoiceLibraryStoreError: LocalizedError, Equatable {
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .write(let detail): return detail
        }
    }
}

/// The library as one JSON file, written 0600 into a 0700 folder by an atomic swap. Deleting the last voice
/// removes the file.
public struct ScribeVoiceLibraryStore: Sendable {
    public static let fileName = "voices.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/Zeus/Voices: next to the app's other private data, never inside a vault.
    public static var standard: ScribeVoiceLibraryStore {
        ScribeVoiceLibraryStore(directory: ZeusPaths.supportDirectory.appendingPathComponent("Voices", isDirectory: true))
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// An empty library when there is no file. A file that cannot be read is an error, never silently emptied.
    public func load() throws -> ScribeVoiceLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ScribeVoiceLibrary() }
        do {
            return try JSONDecoder.library.decode(ScribeVoiceLibrary.self, from: Data(contentsOf: fileURL))
        } catch {
            throw ScribeVoiceLibraryStoreError.write("Couldn't read the saved voices: \(error.localizedDescription)")
        }
    }

    public func save(_ library: ScribeVoiceLibrary) throws {
        let fileManager = FileManager.default
        if library.isEmpty {
            do {
                if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
                return
            } catch {
                throw ScribeVoiceLibraryStoreError.write("Couldn't delete the saved voices: \(error.localizedDescription)")
            }
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder.library.encode(library)
            let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
            guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw ScribeVoiceLibraryStoreError.write("Couldn't create \(temporary.lastPathComponent).")
            }
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: fileURL)
                }
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        } catch let error as ScribeVoiceLibraryStoreError {
            throw error
        } catch {
            throw ScribeVoiceLibraryStoreError.write("Couldn't save the voices: \(error.localizedDescription)")
        }
    }
}

private extension JSONEncoder {
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
