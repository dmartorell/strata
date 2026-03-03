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
        rootURL = musicURL.appendingPathComponent("Strata", isDirectory: true)
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
}
