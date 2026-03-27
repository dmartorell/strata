import Foundation
import Observation

struct RehearsalWord: Sendable {
    let word: String
    let chord: String?
    let wordStart: Double
}

struct RehearsalLine: Identifiable, Sendable {
    let id: UUID
    let start: Double
    let end: Double
    let words: [RehearsalWord]
}

@Observable
@MainActor
final class PlayerViewModel {
    let song: SongEntry
    private(set) var lyrics: [LyricLine] = []
    private(set) var chords: [ChordEntry] = []
    private(set) var isLoadingLyrics: Bool = false
    var showTransposed: Bool = false
    var lyricsOffset: Double = 0

    let engine: PlaybackEngine
    private let cacheManager: CacheManager
    private let libraryStore: LibraryStore
    @ObservationIgnored private var lastLineIndex: Int = 0
    @ObservationIgnored private var lastChordIndex: Int = 0

    init(
        song: SongEntry,
        engine: PlaybackEngine,
        cacheManager: CacheManager,
        libraryStore: LibraryStore
    ) {
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
        lyricsOffset = song.lyricsOffset ?? 0

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
                var songs = libraryStore.songs
                if let idx = songs.firstIndex(where: { $0.id == song.id }) {
                    songs[idx].key = inferredKey
                    try? await cacheManager.writeLibraryIndex(songs)
                    await libraryStore.loadFromDisk()
                }
            }
        }
    }

    func loadRemoteMetadata() async {
        if lyrics.isEmpty {
            isLoadingLyrics = true
            if let lyricsFile = await LRCLibService.shared.fetchLyrics(
                title: song.title,
                artist: song.artist,
                duration: song.duration
            ) {
                lyrics = lyricsFile.segments
                try? await cacheManager.writeLyrics(songID: song.id, lyricsFile: lyricsFile)
            }
            isLoadingLyrics = false
        }
    }

    var currentLine: LyricLine? {
        let t = engine.currentTime + lyricsOffset
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

    var currentChord: ChordEntry? {
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

    var rehearsalLines: [RehearsalLine] {
        let placeholders = Self.placeholderChords
        let filteredChords = chords.filter { !placeholders.contains($0.chord) }

        return lyrics.enumerated().map { (lineIdx, line) in
            let windowStart = lineIdx > 0 ? lyrics[lineIdx - 1].end : 0.0
            let windowEnd = line.end

            let lineChords = filteredChords.filter { $0.start >= windowStart && $0.start < windowEnd }

            var chordForWord: [Int: ChordEntry] = [:]
            for chord in lineChords {
                let wordIdx: Int
                if let idx = line.words.firstIndex(where: { $0.start >= chord.start }) {
                    wordIdx = idx
                } else if !line.words.isEmpty {
                    wordIdx = line.words.count - 1
                } else {
                    continue
                }
                if chordForWord[wordIdx] == nil {
                    chordForWord[wordIdx] = chord
                }
            }

            let words: [RehearsalWord] = line.words.enumerated().map { (wordIdx, word) in
                let chordName: String?
                if let raw = chordForWord[wordIdx]?.chord {
                    if showTransposed && engine.pitchSemitones != 0 {
                        chordName = ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
                    } else {
                        chordName = raw
                    }
                } else {
                    chordName = nil
                }
                return RehearsalWord(word: word.word, chord: chordName, wordStart: word.start)
            }

            return RehearsalLine(id: line.id, start: line.start, end: line.end, words: words)
        }
    }

    func saveLyricsOffset() async {
        var songs = libraryStore.songs
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx].lyricsOffset = lyricsOffset
            try? await cacheManager.writeLibraryIndex(songs)
            await libraryStore.loadFromDisk()
        }
    }

    func savePitchOffset() async {
        var songs = libraryStore.songs
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx].pitchOffset = engine.pitchSemitones
            try? await cacheManager.writeLibraryIndex(songs)
            await libraryStore.loadFromDisk()
        }
    }

    func saveDisplayMode(showLyrics: Bool, showChords: Bool, showRehearsalSheet: Bool = false) async {
        let mode: SongEntry.DisplayMode
        if showRehearsalSheet {
            mode = .rehearsalSheet
        } else {
            mode = switch (showLyrics, showChords) {
            case (true, true): .lyricsAndChords
            case (false, true): .chords
            default: .lyrics
            }
        }
        var songs = libraryStore.songs
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx].displayMode = mode
            try? await cacheManager.writeLibraryIndex(songs)
            await libraryStore.loadFromDisk()
        }
    }
}
