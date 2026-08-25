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
            let indexed = try await cacheManager.readLibraryIndex()
            let root = await cacheManager.rootURL
            let indexedIDs = Set(indexed.map(\.id))
            let recovered = recoverEntries(in: root, excluding: indexedIDs)
            var needsWrite = recovered.isEmpty == false

            let persisted = (indexed + recovered).map { entry -> SongEntry in
                guard entry.artist == nil,
                      let fileName = entry.fileName,
                      let artist = SongEntry.parseArtistAndTitle(from: fileName).artist
                else { return entry }
                needsWrite = true
                let parsed = SongEntry.parseArtistAndTitle(from: fileName)
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
                    isPlaceholder: entry.isPlaceholder,
                    importStatus: entry.importStatus
                )
            }
            if needsWrite {
                try? await cacheManager.writeLibraryIndex(persisted)
            }

            let available = persisted.filter { entry in
                let directory = root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
                return FileManager.default.fileExists(atPath: directory.path)
            }
            let placeholders = songs.filter { $0.isPlaceholder == true }
            var merged = placeholders + available.sorted { $0.addedAt > $1.addedAt }
            for placeholder in placeholders {
                merged.removeAll { $0.id == placeholder.id && $0.isPlaceholder != true }
            }
            songs = merged
            loadError = nil
        } catch {
            songs = []
            loadError = error
        }
    }

    private func recoverEntries(in rootURL: URL, excluding indexedIDs: Set<UUID>) -> [SongEntry] {
        guard let directoryURLs = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return directoryURLs.compactMap { directoryURL in
            guard let id = UUID(uuidString: directoryURL.lastPathComponent),
                  indexedIDs.contains(id) == false,
                  containsCachedAudio(in: directoryURL)
            else { return nil }

            let metadataURL = directoryURL.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(SongMetadata.self, from: data)
            else { return nil }

            let fileName = metadata.originalFilename
            let parsed = fileName.map(SongEntry.parseArtistAndTitle)
            let metadataTitle = URL(fileURLWithPath: metadata.title)
                .deletingPathExtension()
                .lastPathComponent
            let parsedTitle = parsed?.title
            let genericTitles = ["audio", "video"]
            let recoveredTitle = if let parsedTitle,
                                    genericTitles.contains(parsedTitle.lowercased()) == false {
                parsedTitle
            } else {
                metadataTitle
            }

            return SongEntry(
                id: id,
                title: recoveredTitle,
                artist: metadata.artist ?? parsed?.artist,
                duration: metadata.durationSeconds ?? 0,
                fileName: fileName,
                sourceHash: "recovered-\(id.uuidString.lowercased())",
                addedAt: processedDate(from: metadata.processedAt) ?? Date.distantPast
            )
        }
    }

    private func containsCachedAudio(in directoryURL: URL) -> Bool {
        let hasOriginal = FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("original.wav").path
        )
        let hasInstrumental = FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("instrumental.wav").path
        )
        let hasLegacyVocals = FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("vocals.wav").path
        )
        return (hasOriginal && hasInstrumental) || hasLegacyVocals
    }

    private func processedDate(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
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

    func song(forYouTubeURL url: URL) -> SongEntry? {
        guard let target = try? YouTubeURL(url: url).canonicalURL else { return nil }
        return songs.first { song in
            guard let sourceURL = song.sourceURL,
                  let url = URL(string: sourceURL),
                  let candidate = try? YouTubeURL(url: url).canonicalURL
            else { return false }
            return candidate == target
        }
    }

    func finderRevealURL(for songID: UUID) async -> URL? {
        guard let song = songs.first(where: { $0.id == songID }) else { return nil }
        return await cacheManager.finderRevealURL(songID: songID, sourceURL: song.sourceURL)
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
