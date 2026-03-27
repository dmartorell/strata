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
            var needsWrite = filtered.count != original.count
            let migrated = filtered.map { entry -> SongEntry in
                guard entry.artist == nil,
                      let fn = entry.fileName,
                      let parsed = Optional(SongEntry.parseArtistAndTitle(from: fn)),
                      let artist = parsed.artist
                else { return entry }
                needsWrite = true
                return SongEntry(
                    id: entry.id,
                    title: parsed.title,
                    artist: artist,
                    duration: entry.duration,
                    sourceURL: entry.sourceURL,
                    fileName: entry.fileName,
                    sourceHash: entry.sourceHash,
                    addedAt: entry.addedAt,
                    pitchOffset: entry.pitchOffset,
                    lyricsOffset: entry.lyricsOffset,
                    key: entry.key,
                    displayMode: entry.displayMode,
                    isPlaceholder: entry.isPlaceholder
                )
            }
            if needsWrite {
                try? await cacheManager.writeLibraryIndex(migrated)
            }
            let placeholders = songs.filter { $0.isPlaceholder == true }
            var merged = placeholders + migrated.sorted { $0.addedAt > $1.addedAt }
            for ph in placeholders {
                merged.removeAll { $0.id == ph.id && $0.isPlaceholder != true }
            }
            songs = merged
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

    func addPlaceholder(_ entry: SongEntry) {
        if entry.importStatus == .queued {
            let insertIndex = songs.firstIndex(where: { $0.isPlaceholder != true }) ?? songs.count
            songs.insert(entry, at: insertIndex)
        } else {
            songs.insert(entry, at: 0)
        }
    }

    func replacePlaceholder(id: UUID, with entry: SongEntry) async {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        songs[index] = entry
        try? await cacheManager.writeLibraryIndex(songs.filter { $0.isPlaceholder != true })
    }

    func removePlaceholder(id: UUID) {
        songs.removeAll { $0.id == id }
    }

    func updatePlaceholderStatus(id: UUID, status: ImportStatus) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        songs[index].importStatus = status
        if status == .active, index != 0 {
            let entry = songs.remove(at: index)
            songs.insert(entry, at: 0)
        }
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
