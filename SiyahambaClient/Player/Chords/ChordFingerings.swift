import Foundation

// Port of server/pipeline/fingerings.py — lookup guitar fingerings from bundled guitar.json
enum ChordFingerings {

    // MARK: - Private constants (mirrors Python ENHARMONIC, SUFFIX_MAP, _DB_KEY_MAP, DB_KEYS)

    private static let enharmonic: [String: String] = [
        "Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb",
    ]

    private static let suffixMap: [String: String] = [
        "": "major",
        "m": "minor",
        "7": "7",
        "maj7": "maj7",
        "m7": "m7",
        "dim": "dim",
        "dim7": "dim7",
        "aug": "aug",
        "m7b5": "m7b5",
        "sus2": "sus2",
        "sus4": "sus4",
        "6": "6",
        "m6": "m6",
        "9": "9",
        "m9": "m9",
        "add9": "add9",
        "5": "5",
        "aug7": "aug7",
        "mmaj7": "mmaj7",
        "maj9": "maj9",
    ]

    private static let suffixToSlashPrefix: [String: String] = [
        "major": "",
        "minor": "m",
        "m9": "m9",
        "7": "7",
    ]

    private static let dbKeyMap: [String: String] = [
        "C#": "Csharp",
        "F#": "Fsharp",
    ]

    private static let dbKeys: Set<String> = [
        "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
    ]

    private static let tuning = [40, 45, 50, 55, 59, 64] // E2 A2 D3 G3 B3 E4

    private static let noteToPitchClass: [String: Int] = [
        "C": 0, "C#": 1, "D": 2, "Eb": 3, "E": 4, "F": 5,
        "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11,
    ]

    // MARK: - Private Codable structures for guitar.json

    private struct GuitarDB: Decodable {
        let chords: [String: [ChordDBEntry]]
    }

    private struct ChordDBEntry: Decodable {
        let suffix: String
        let positions: [ChordDBPosition]
    }

    private struct ChordDBPosition: Decodable {
        let frets: [Int]
        let fingers: [Int]
        let baseFret: Int
        let barres: [Int]
    }

    // MARK: - Lazy-loaded database

    nonisolated(unsafe) private static var db: GuitarDB? = {
        guard let url = Bundle.main.url(forResource: "guitar", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(GuitarDB.self, from: data)
        else { return nil }
        return parsed
    }()

    // MARK: - Public API

    static func lookup(_ chordName: String) -> [ChordPosition] {
        var bassNote: String?
        if let slashIdx = chordName.firstIndex(of: "/") {
            let raw = String(chordName[chordName.index(after: slashIdx)...])
            let normalized = enharmonic[raw] ?? raw
            if dbKeys.contains(normalized) {
                bassNote = normalized
            }
        }

        guard let (key, suffix) = chordNameToKeySuffix(chordName) else { return [] }
        let dbKey = dbKeyMap[key] ?? key
        guard let entries = db?.chords[dbKey] else { return [] }

        if let bass = bassNote, let slashPrefix = suffixToSlashPrefix[suffix] {
            let slashSuffix = slashPrefix.isEmpty ? "/\(bass)" : "\(slashPrefix)/\(bass)"
            if let entry = entries.first(where: { $0.suffix == slashSuffix }) {
                return entry.positions.prefix(3).map { toChordPosition($0) }
            }
        }

        guard let entry = entries.first(where: { $0.suffix == suffix }) else { return [] }
        var result = entry.positions.prefix(3).map { toChordPosition($0) }
        if let bass = bassNote {
            result = reorderByBass(result, bassNote: bass)
        }
        return result
    }

    // MARK: - Private helpers

    private static func toChordPosition(_ p: ChordDBPosition) -> ChordPosition {
        ChordPosition(frets: p.frets, fingers: p.fingers, baseFret: p.baseFret, barres: p.barres)
    }

    private static func bassPitchClass(_ pos: ChordPosition) -> Int? {
        for s in 0..<6 {
            if pos.frets[s] != -1 {
                return (tuning[s] + (pos.baseFret - 1) + pos.frets[s]) % 12
            }
        }
        return nil
    }

    private static func reorderByBass(_ positions: [ChordPosition], bassNote: String) -> [ChordPosition] {
        guard let target = noteToPitchClass[bassNote] else { return positions }
        let matching = positions.filter { bassPitchClass($0) == target }
        let rest = positions.filter { bassPitchClass($0) != target }
        return matching + rest
    }

    private static func chordNameToKeySuffix(_ chord: String) -> (key: String, suffix: String)? {
        guard !chord.isEmpty, chord != "N", chord != "-" else { return nil }

        var normalized = chord

        if let slashIdx = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIdx])
        }

        let root: String
        let quality: String
        if normalized.count >= 2 {
            let secondChar = normalized[normalized.index(normalized.startIndex, offsetBy: 1)]
            if secondChar == "#" || secondChar == "b" {
                root = String(normalized.prefix(2))
                quality = String(normalized.dropFirst(2))
            } else {
                root = String(normalized.prefix(1))
                quality = String(normalized.dropFirst(1))
            }
        } else {
            root = normalized
            quality = ""
        }

        let normalizedRoot = enharmonic[root] ?? root

        guard dbKeys.contains(normalizedRoot) else { return nil }
        guard let mappedSuffix = suffixMap[quality] else { return nil }

        return (normalizedRoot, mappedSuffix)
    }
}
