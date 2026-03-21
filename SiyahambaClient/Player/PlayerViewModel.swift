import Foundation
import Observation

@Observable
@MainActor
final class PlayerViewModel {
    let song: SongEntry
    private(set) var lyrics: [LyricLine] = []
    private(set) var chords: [ChordEntry] = []
    var showTransposed: Bool = false

    let engine: PlaybackEngine
    private let cacheManager: CacheManager
    private let libraryStore: LibraryStore

    private var lastLineIndex: Int = 0
    private var lastChordIndex: Int = 0

    init(song: SongEntry, engine: PlaybackEngine, cacheManager: CacheManager, libraryStore: LibraryStore) {
        self.song = song
        self.engine = engine
        self.cacheManager = cacheManager
        self.libraryStore = libraryStore
    }

    func load() async throws {
        let stemNames = ["vocals", "drums", "bass", "other"]
        var stemURLs: [URL] = []
        for name in stemNames {
            stemURLs.append(await cacheManager.stemURL(songID: song.id, stem: name))
        }
        try engine.load(stemURLs: stemURLs)
        engine.setPitch(semitones: song.pitchOffset ?? 0)

        let lyricsURL = await cacheManager.lyricsURL(songID: song.id)
        if FileManager.default.fileExists(atPath: lyricsURL.path) {
            do {
                let data = try Data(contentsOf: lyricsURL)
                let lyricsFile = try JSONDecoder().decode(LyricsFile.self, from: data)
                lyrics = lyricsFile.segments
            } catch {}
        }

        let chordsURL = await cacheManager.chordsURL(songID: song.id)
        if FileManager.default.fileExists(atPath: chordsURL.path) {
            do {
                let data = try Data(contentsOf: chordsURL)
                if let chordsFile = try? JSONDecoder().decode(ChordsFile.self, from: data) {
                    chords = chordsFile.chords
                } else {
                    chords = try JSONDecoder().decode([ChordEntry].self, from: data)
                }
                if !chords.isEmpty, chords.last?.end == nil {
                    chords[chords.count - 1].end = engine.duration
                }
            } catch {}
        }

        if song.key == nil {
            if let inferredKey = ChordTransposer.inferKey(from: chords) {
                var updated = song
                updated.key = inferredKey
                var songs = libraryStore.songs
                if let idx = songs.firstIndex(where: { $0.id == song.id }) {
                    songs[idx] = updated
                    try? await cacheManager.writeLibraryIndex(songs)
                    await libraryStore.loadFromDisk()
                }
            }
        }
    }

    var currentLine: LyricLine? {
        let t = engine.currentTime
        if lastLineIndex < lyrics.count {
            let line = lyrics[lastLineIndex]
            if t >= line.start && t < line.end {
                return line
            }
            if lastLineIndex + 1 < lyrics.count {
                let next = lyrics[lastLineIndex + 1]
                if t >= next.start && t < next.end {
                    lastLineIndex += 1
                    return next
                }
            }
        }
        for (i, line) in lyrics.enumerated() {
            if t >= line.start && t < line.end {
                lastLineIndex = i
                return line
            }
        }
        return nil
    }

    var currentWord: LyricWord? {
        guard let line = currentLine else { return nil }
        let t = engine.currentTime
        return line.words.first { t >= $0.start && t < $0.end }
    }

    var currentChord: ChordEntry? {
        guard engine.isPlaying else { return nil }
        let t = engine.currentTime
        var bestIdx: Int? = nil

        if lastChordIndex < chords.count {
            let chord = chords[lastChordIndex]
            if chord.start <= t {
                let nextIdx = lastChordIndex + 1
                if nextIdx >= chords.count || chords[nextIdx].start > t {
                    return chord
                }
                if nextIdx < chords.count && chords[nextIdx].start <= t {
                    lastChordIndex = nextIdx
                    bestIdx = nextIdx
                }
            }
        }

        if bestIdx == nil {
            for (i, chord) in chords.enumerated() {
                if chord.start <= t {
                    bestIdx = i
                } else {
                    break
                }
            }
        }

        guard let idx = bestIdx else { return nil }
        lastChordIndex = idx
        return chords[idx]
    }

    var nextChord: ChordEntry? {
        guard let current = currentChord,
              let idx = chords.firstIndex(where: { $0.id == current.id }),
              idx + 1 < chords.count else { return nil }
        return chords[idx + 1]
    }

    private static let placeholderChords: Set<String> = ["N", "-", ""]

    var displayChord: String {
        guard let raw = currentChord?.chord, !Self.placeholderChords.contains(raw) else { return "" }
        if showTransposed && engine.pitchSemitones != 0 {
            return ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
        }
        return raw
    }

    var displayNextChord: String {
        guard let raw = nextChord?.chord, !Self.placeholderChords.contains(raw) else { return "" }
        if showTransposed && engine.pitchSemitones != 0 {
            return ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
        }
        return raw
    }

    func savePitchOffset() async {
        var updated = song
        updated.pitchOffset = engine.pitchSemitones
        var songs = libraryStore.songs
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx] = updated
            try? await cacheManager.writeLibraryIndex(songs)
            await libraryStore.loadFromDisk()
        }
    }

    func saveDisplayMode(showLyrics: Bool, showChords: Bool) async {
        let mode: SongEntry.DisplayMode = switch (showLyrics, showChords) {
        case (true, true): .lyricsAndChords
        case (true, false): .lyrics
        case (false, true): .chords
        default: .waveforms
        }
        var updated = song
        updated.displayMode = mode
        var songs = libraryStore.songs
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx] = updated
            try? await cacheManager.writeLibraryIndex(songs)
            await libraryStore.loadFromDisk()
        }
    }
}
