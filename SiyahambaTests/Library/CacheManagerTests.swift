import Foundation
import Testing
@testable import Siyahamba

struct CacheManagerTests {
    @Test func finderRevealURLPrioritizesExistingSourceMP3() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let cacheManager = try CacheManager(rootURL: rootURL)
        let songID = UUID()
        let songDirectory = await cacheManager.songDirectory(for: songID)
        try FileManager.default.createDirectory(at: songDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("wav".utf8).write(to: songDirectory.appendingPathComponent("original.wav"))
        let sourceMP3 = sourceDirectory.appendingPathComponent("cancion.mp3")
        try Data("mp3".utf8).write(to: sourceMP3)

        let result = await cacheManager.finderRevealURL(
            songID: songID,
            sourceURL: sourceMP3.absoluteString
        )

        #expect(result == sourceMP3)
    }

    @Test func finderRevealURLReturnsNilWithoutExistingSourceMP3() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)
        let songID = UUID()
        let songDirectory = await cacheManager.songDirectory(for: songID)
        try FileManager.default.createDirectory(at: songDirectory, withIntermediateDirectories: true)
        try Data("wav".utf8).write(to: songDirectory.appendingPathComponent("original.wav"))
        try Data("mp3".utf8).write(to: songDirectory.appendingPathComponent("cancion.mp3"))

        let result = await cacheManager.finderRevealURL(songID: songID, sourceURL: nil)

        #expect(result == nil)
    }

    @Test func finderRevealURLReturnsNilWhenSongIsNotCached() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cacheManager = try CacheManager(rootURL: rootURL)

        let result = await cacheManager.finderRevealURL(songID: UUID(), sourceURL: nil)

        #expect(result == nil)
    }
}
