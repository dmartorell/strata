import Foundation
import Testing
@testable import Siyahamba

@MainActor
struct LibraryStoreTests {
    @Test func loadFromDiskDoesNotDeleteIndexEntriesWithMissingDirectories() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)
        let missingSong = makeSongEntry(id: UUID(), title: "No disponible")
        try await cacheManager.writeLibraryIndex([missingSong])
        let store = LibraryStore(cacheManager: cacheManager)

        await store.loadFromDisk()

        let persisted = try await cacheManager.readLibraryIndex()
        #expect(persisted.map(\.id) == [missingSong.id])
        #expect(store.songs.isEmpty)
    }

    @Test func loadFromDiskRecoversUnindexedCachedSongFromMetadata() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)
        let songID = UUID()
        let songDirectory = await cacheManager.songDirectory(for: songID)
        try FileManager.default.createDirectory(at: songDirectory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: songDirectory.appendingPathComponent("original.wav"))
        try Data("audio".utf8).write(to: songDirectory.appendingPathComponent("instrumental.wav"))
        let metadata = SongMetadata(
            title: "Canción",
            artist: "Artista",
            durationSeconds: 123,
            sampleRate: 44_100,
            sourceType: "file",
            processedAt: "2026-08-25T10:00:00.000000Z",
            originalFilename: "audio.mp3"
        )
        try JSONEncoder().encode(metadata)
            .write(to: songDirectory.appendingPathComponent("metadata.json"))
        let store = LibraryStore(cacheManager: cacheManager)

        await store.loadFromDisk()

        let recovered = try #require(store.songs.first)
        #expect(recovered.id == songID)
        #expect(recovered.artist == "Artista")
        #expect(recovered.title == "Canción")
        #expect(recovered.duration == 123)
        let persisted = try await cacheManager.readLibraryIndex()
        #expect(persisted.contains(where: { $0.id == songID }))
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeSongEntry(id: UUID, title: String) -> SongEntry {
        SongEntry(
            id: id,
            title: title,
            duration: 60,
            sourceHash: "hash-\(id.uuidString)",
            addedAt: Date()
        )
    }
}
