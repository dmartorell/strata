import Foundation
import Observation

struct ChordOverride: Codable, Sendable {
    let lineIndex: Int
    let wordIndex: Int
    let chord: String
}

struct DragSource {
    let line: Int
    let word: Int
}

struct RehearsalWord: Identifiable, Sendable {
    let id: String
    let word: String
    let chord: String?
    let wordStart: Double
    let overrideIndex: Int?
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
    var chordOverrides: [ChordOverride] = []
    var isEditingChord: Bool = false
    var draggingChordSource: DragSource? = nil

    // Cached derived state — updated via tick(), not recomputed on every body evaluation
    private(set) var currentLine: LyricLine? = nil
    private(set) var currentChord: ChordEntry? = nil
    private(set) var nextChord: ChordEntry? = nil
    private(set) var displayChord: String = ""
    private(set) var displayNextChord: String = ""
    private(set) var rehearsalLines: [RehearsalLine] = []

    let engine: PlaybackEngine
    private let cacheManager: CacheManager
    private let libraryStore: LibraryStore
    @ObservationIgnored private var lastLineIndex: Int = 0
    @ObservationIgnored private var lastChordIndex: Int = 0
    @ObservationIgnored private var lastShowTransposed: Bool = false
    @ObservationIgnored private var lastPitchSemitones: Int = 0

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

        chordOverrides = (try? await cacheManager.readChordOverrides(songID: song.id)) ?? []

        lastShowTransposed = showTransposed
        lastPitchSemitones = engine.pitchSemitones
        rebuildRehearsalLines()
        updateCurrentLine()
        updateCurrentChord()
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
                rebuildRehearsalLines()
            }
            isLoadingLyrics = false
        }
    }

    // Called by PlaybackEngine's timer on every frame
    func tick() {
        if showTransposed != lastShowTransposed || engine.pitchSemitones != lastPitchSemitones {
            lastShowTransposed = showTransposed
            lastPitchSemitones = engine.pitchSemitones
            rebuildRehearsalLines()
        }
        updateCurrentLine()
        updateCurrentChord()
    }

    private func updateCurrentLine() {
        let t = engine.currentTime + lyricsOffset
        var foundLine: LyricLine? = nil

        if lastLineIndex < lyrics.count {
            let line = lyrics[lastLineIndex]
            if t >= line.start && t < line.end {
                foundLine = line
            } else if lastLineIndex + 1 < lyrics.count {
                let next = lyrics[lastLineIndex + 1]
                if t >= next.start && t < next.end {
                    lastLineIndex += 1
                    foundLine = next
                }
            }
        }

        if foundLine == nil {
            for (i, line) in lyrics.enumerated() {
                if t >= line.start && t < line.end {
                    lastLineIndex = i
                    foundLine = line
                    break
                }
            }
        }

        if foundLine?.id != currentLine?.id {
            currentLine = foundLine
        }
    }

    private func updateCurrentChord() {
        let t = engine.currentTime
        var bestIdx: Int? = nil

        if lastChordIndex < chords.count {
            let chord = chords[lastChordIndex]
            if chord.start <= t {
                let nextIdx = lastChordIndex + 1
                if nextIdx >= chords.count || chords[nextIdx].start > t {
                    bestIdx = lastChordIndex
                } else if nextIdx < chords.count && chords[nextIdx].start <= t {
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

        let newChord: ChordEntry? = bestIdx.map { chords[$0] }
        if let idx = bestIdx { lastChordIndex = idx }

        if newChord?.id != currentChord?.id {
            currentChord = newChord

            // Update next chord
            let newNext: ChordEntry?
            if let current = newChord,
               let idx = chords.firstIndex(where: { $0.id == current.id }),
               idx + 1 < chords.count {
                newNext = chords[idx + 1]
            } else {
                newNext = nil
            }
            nextChord = newNext

            // Update display strings
            let placeholders = Self.placeholderChords
            if let raw = newChord?.chord, !placeholders.contains(raw) {
                if showTransposed && engine.pitchSemitones != 0 {
                    displayChord = ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
                } else {
                    displayChord = raw
                }
            } else {
                displayChord = ""
            }

            if let raw = newNext?.chord, !placeholders.contains(raw) {
                if showTransposed && engine.pitchSemitones != 0 {
                    displayNextChord = ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
                } else {
                    displayNextChord = raw
                }
            } else {
                displayNextChord = ""
            }
        }
    }

    private static let placeholderChords: Set<String> = ["N", "-", ""]

    private func rebuildRehearsalLines() {
        let placeholders = Self.placeholderChords
        let filteredChords = chords.filter { !placeholders.contains($0.chord) }

        rehearsalLines = lyrics.enumerated().map { lineIndex, line in
            let words: [RehearsalWord] = line.words.enumerated().map { wordIndex, word in
                let matchedChord = filteredChords.last(where: { chord in
                    chord.start >= word.start && chord.start < word.end
                })
                let chordName: String?
                if let raw = matchedChord?.chord {
                    if showTransposed && engine.pitchSemitones != 0 {
                        chordName = ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
                    } else {
                        chordName = raw
                    }
                } else {
                    chordName = nil
                }
                return RehearsalWord(id: "\(lineIndex)-\(wordIndex)", word: word.word, chord: chordName, wordStart: word.start, overrideIndex: nil)
            }

            // Attach any chord that falls before this line's first word to the first word
            var finalWords = words
            if !finalWords.isEmpty && finalWords[0].chord == nil {
                let lineStart = line.start
                let firstWordStart = line.words.first?.start ?? lineStart
                let orphanChord = filteredChords.last(where: { chord in
                    chord.start >= lineStart && chord.start < firstWordStart
                })
                if let raw = orphanChord?.chord {
                    let chordName: String
                    if showTransposed && engine.pitchSemitones != 0 {
                        chordName = ChordTransposer.transpose(raw, semitones: engine.pitchSemitones)
                    } else {
                        chordName = raw
                    }
                    let original = finalWords[0]
                    finalWords[0] = RehearsalWord(id: original.id, word: original.word, chord: chordName, wordStart: original.wordStart, overrideIndex: nil)
                }
            }

            // Apply chord overrides for this line
            let lineOverrides = chordOverrides.filter { $0.lineIndex == lineIndex }
            for override in lineOverrides {
                guard override.wordIndex < finalWords.count else { continue }
                let original = finalWords[override.wordIndex]
                let newChord: String?
                if override.chord.isEmpty {
                    newChord = nil
                } else if showTransposed && engine.pitchSemitones != 0 {
                    newChord = ChordTransposer.transpose(override.chord, semitones: engine.pitchSemitones)
                } else {
                    newChord = override.chord
                }
                finalWords[override.wordIndex] = RehearsalWord(id: original.id, word: original.word, chord: newChord, wordStart: original.wordStart, overrideIndex: override.wordIndex)
            }

            // Append tail chords (overrides beyond last word)
            let tailOverrides = lineOverrides
                .filter { $0.wordIndex >= finalWords.count && !$0.chord.isEmpty }
                .sorted { $0.wordIndex < $1.wordIndex }
            for override in tailOverrides {
                let chordName: String
                if showTransposed && engine.pitchSemitones != 0 {
                    chordName = ChordTransposer.transpose(override.chord, semitones: engine.pitchSemitones)
                } else {
                    chordName = override.chord
                }
                finalWords.append(RehearsalWord(id: "\(lineIndex)-tail-\(override.wordIndex)", word: "", chord: chordName, wordStart: line.end, overrideIndex: override.wordIndex))
            }

            return RehearsalLine(id: line.id, start: line.start, end: line.end, words: finalWords)
        }
    }

    func saveChordOverrides() async {
        try? await cacheManager.writeChordOverrides(songID: song.id, overrides: chordOverrides)
    }

    func applyChordOverride(lineIndex: Int, fromWordIndex: Int, toWordIndex: Int) {
        guard lineIndex < rehearsalLines.count else { return }
        let line = rehearsalLines[lineIndex]
        guard fromWordIndex < line.words.count else { return }

        guard let displayedChord = line.words[fromWordIndex].chord else { return }
        let rawChord: String
        if showTransposed && engine.pitchSemitones != 0 {
            rawChord = ChordTransposer.transpose(displayedChord, semitones: -engine.pitchSemitones)
        } else {
            rawChord = displayedChord
        }

        let baseWordCount = lyrics[lineIndex].words.count
        let sourceOverrideIndex = line.words[fromWordIndex].overrideIndex ?? fromWordIndex
        let fromIsTail = sourceOverrideIndex >= baseWordCount

        // Clean up source
        chordOverrides.removeAll { $0.lineIndex == lineIndex && $0.wordIndex == sourceOverrideIndex }
        if !fromIsTail {
            chordOverrides.append(ChordOverride(lineIndex: lineIndex, wordIndex: sourceOverrideIndex, chord: ""))
        }

        if toWordIndex >= baseWordCount {
            let existingTailIndices = chordOverrides
                .filter { $0.lineIndex == lineIndex && $0.wordIndex >= baseWordCount && !$0.chord.isEmpty }
                .map(\.wordIndex)
            let nextTailIndex = (existingTailIndices.max() ?? (baseWordCount - 1)) + 1
            chordOverrides.append(ChordOverride(lineIndex: lineIndex, wordIndex: nextTailIndex, chord: rawChord))
        } else {
            chordOverrides.removeAll { $0.lineIndex == lineIndex && $0.wordIndex == toWordIndex }
            chordOverrides.append(ChordOverride(lineIndex: lineIndex, wordIndex: toWordIndex, chord: rawChord))
        }

        draggingChordSource = nil
        rebuildRehearsalLines()
        Task { await saveChordOverrides() }
    }

    func deleteChordOverride(lineIndex: Int, wordIndex: Int) {
        let realIndex = resolveOverrideIndex(lineIndex: lineIndex, wordIndex: wordIndex)
        let baseWordCount = lyrics[lineIndex].words.count
        chordOverrides.removeAll { $0.lineIndex == lineIndex && $0.wordIndex == realIndex }
        if realIndex < baseWordCount {
            chordOverrides.append(ChordOverride(lineIndex: lineIndex, wordIndex: realIndex, chord: ""))
        }
        draggingChordSource = nil
        rebuildRehearsalLines()
        Task { await saveChordOverrides() }
    }

    func addChordOverride(lineIndex: Int, wordIndex: Int, chord: String) {
        let realIndex = resolveOverrideIndex(lineIndex: lineIndex, wordIndex: wordIndex)
        chordOverrides.removeAll { $0.lineIndex == lineIndex && $0.wordIndex == realIndex }
        chordOverrides.append(ChordOverride(lineIndex: lineIndex, wordIndex: realIndex, chord: chord))
        draggingChordSource = nil
        rebuildRehearsalLines()
        Task { await saveChordOverrides() }
    }

    private func resolveOverrideIndex(lineIndex: Int, wordIndex: Int) -> Int {
        guard lineIndex < rehearsalLines.count, wordIndex < rehearsalLines[lineIndex].words.count else { return wordIndex }
        return rehearsalLines[lineIndex].words[wordIndex].overrideIndex ?? wordIndex
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
