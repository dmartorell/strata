import Foundation
import Observation

@Observable
@MainActor
final class LibraryStore {
    private(set) var songs: [SongEntry] = []
    private(set) var loadError: Error? = nil

    private let cacheManager: CacheManager

    init(cacheManager: CacheManager) {
        self.cacheManager = cacheManager
    }

    func loadFromDisk() async {
        do {
            let original = try await cacheManager.readLibraryIndex()
            let root = await cacheManager.rootURL
            let filtered = original.filter { entry in
                let dir = root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
                return FileManager.default.fileExists(atPath: dir.path)
            }
            if filtered.count != original.count {
                try? await cacheManager.writeLibraryIndex(filtered)
            }
            songs = filtered.sorted { $0.addedAt > $1.addedAt }
            loadError = nil
        } catch {
            songs = []
            loadError = error
        }
    }

    func addSong(_ entry: SongEntry) async {
        songs.insert(entry, at: 0)
        try? await cacheManager.writeLibraryIndex(songs)
    }

    func isCached(sourceHash: String) -> Bool {
        songs.contains { $0.sourceHash == sourceHash }
    }

    func deleteSongs(ids: Set<UUID>) async {
        let remaining = songs.filter { !ids.contains($0.id) }
        for id in ids {
            let dir = await cacheManager.songDirectory(for: id)
            try? FileManager.default.removeItem(at: dir)
        }
        try? await cacheManager.writeLibraryIndex(remaining)
        songs = remaining
    }
}
