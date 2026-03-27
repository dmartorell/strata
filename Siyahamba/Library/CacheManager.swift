import CryptoKit
import Foundation

// MARK: - Protocol

protocol CacheManagerProtocol: Actor {
    var rootURL: URL { get }
    func songDirectory(for id: UUID) -> URL
    func readLibraryIndex() throws -> [SongEntry]
    func writeLibraryIndex(_ songs: [SongEntry]) throws
    func stemURL(songID: UUID, stem: String) -> URL
    func lyricsURL(songID: UUID) -> URL
    func chordsURL(songID: UUID) -> URL
    func writeLyrics(songID: UUID, lyricsFile: LyricsFile) throws
    func sha256(of fileURL: URL) throws -> String
    func materializeSong(id: UUID, from tempDir: URL) throws
}

// MARK: - Implementation

actor CacheManager: CacheManagerProtocol {
    let rootURL: URL

    init() throws {
        let musicURL = try FileManager.default.url(
            for: .musicDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        rootURL = musicURL.appendingPathComponent("Siyahamba", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func songDirectory(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }
}

// MARK: - Library index read/write

extension CacheManager {
    private var libraryIndexURL: URL {
        rootURL.appendingPathComponent("library.json")
    }

    func readLibraryIndex() throws -> [SongEntry] {
        guard FileManager.default.fileExists(atPath: libraryIndexURL.path) else {
            return []
        }
        let data = try Data(contentsOf: libraryIndexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SongEntry].self, from: data)
    }

    func writeLibraryIndex(_ songs: [SongEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(songs)
        try data.write(to: libraryIndexURL, options: .atomic)
    }
}

// MARK: - URL helpers para stems/JSON

extension CacheManager {
    func stemURL(songID: UUID, stem: String) -> URL {
        songDirectory(for: songID).appendingPathComponent("\(stem).wav")
    }

    func lyricsURL(songID: UUID) -> URL {
        songDirectory(for: songID).appendingPathComponent("lyrics.json")
    }

    func chordsURL(songID: UUID) -> URL {
        songDirectory(for: songID).appendingPathComponent("chords.json")
    }

    func writeLyrics(songID: UUID, lyricsFile: LyricsFile) throws {
        let dir = songDirectory(for: songID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(lyricsFile)
        try data.write(to: lyricsURL(songID: songID), options: .atomic)
    }
}

// MARK: - SHA256 incremental para archivos locales

extension CacheManager {
    func sha256(of fileURL: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let chunkSize = 65_536  // 64 KB chunks — nunca carga mas de 64 KB en memoria
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Chord overrides per song

extension CacheManager {
    func chordOverridesURL(songID: UUID) -> URL {
        songDirectory(for: songID).appendingPathComponent("chord_overrides.json")
    }

    func readChordOverrides(songID: UUID) throws -> [ChordOverride] {
        let url = chordOverridesURL(songID: songID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ChordOverride].self, from: data)
    }

    func writeChordOverrides(songID: UUID, overrides: [ChordOverride]) throws {
        let url = chordOverridesURL(songID: songID)
        let data = try JSONEncoder().encode(overrides)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Materializacion de cancion desde tempDir

extension CacheManager {
    func materializeSong(id: UUID, from tempDir: URL) throws {
        let destDir = songDirectory(for: id)
        try FileManager.default.createDirectory(
            at: destDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let requiredFiles = ["vocals.wav", "drums.wav", "bass.wav", "other.wav",
                              "chords.json", "metadata.json"]
        for filename in requiredFiles {
            let src = tempDir.appendingPathComponent(filename)
            let dest = destDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: src, to: dest)
        }
        let optionalFiles = ["lyrics.json"]
        for filename in optionalFiles {
            let src = tempDir.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dest = destDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: src, to: dest)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }
}
