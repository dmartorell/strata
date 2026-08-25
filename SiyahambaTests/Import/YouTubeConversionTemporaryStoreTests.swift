import Foundation
import Testing
@testable import Siyahamba

struct YouTubeConversionTemporaryStoreTests {
    @Test func removesAllAbandonedConversions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = YouTubeConversionTemporaryStore(rootURL: rootURL)
        let firstDirectory = try store.makeConversionDirectory()
        let secondDirectory = try store.makeConversionDirectory()
        try Data("audio".utf8).write(to: firstDirectory.appendingPathComponent("audio.mp3"))
        try Data("audio".utf8).write(to: secondDirectory.appendingPathComponent("audio.m4a"))

        try store.removeAll()

        #expect(!FileManager.default.fileExists(atPath: rootURL.path))
    }

    @Test func cleanupAllowsMissingDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = YouTubeConversionTemporaryStore(rootURL: rootURL)

        try store.removeAll()

        #expect(!FileManager.default.fileExists(atPath: rootURL.path))
    }
}
