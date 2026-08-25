import Foundation
import Testing
@testable import Siyahamba

struct CacheManagerTests {
    @Test func finderRevealURLReturnsExistingSourceMP3() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)
        let sourceMP3 = rootURL.appendingPathComponent("cancion.mp3")
        try Data("mp3".utf8).write(to: sourceMP3)

        let result = await cacheManager.finderRevealURL(
            songID: UUID(),
            sourceURL: sourceMP3.absoluteString
        )

        #expect(result == sourceMP3)
    }

    @Test func rawAudioURLReturnsOriginalWAV() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)
        let songID = UUID()
        let songDirectory = await cacheManager.songDirectory(for: songID)
        let originalURL = songDirectory.appendingPathComponent("original.wav")
        try FileManager.default.createDirectory(at: songDirectory, withIntermediateDirectories: true)
        try Data("wav".utf8).write(to: originalURL)

        let result = await cacheManager.rawAudioURL(songID: songID)

        #expect(result == originalURL)
    }

    @Test func rawAudioURLReturnsNilWhenOriginalWAVIsMissing() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)

        let result = await cacheManager.rawAudioURL(songID: UUID())

        #expect(result == nil)
    }
}
