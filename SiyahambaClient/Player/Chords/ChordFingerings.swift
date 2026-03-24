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

    private static let dbKeyMap: [String: String] = [
        "C#": "Csharp",
        "F#": "Fsharp",
    ]

    private static let dbKeys: Set<String> = [
        "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
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
        guard let (key, suffix) = chordNameToKeySuffix(chordName) else { return [] }
        let dbKey = dbKeyMap[key] ?? key
        guard let entries = db?.chords[dbKey] else { return [] }
        guard let entry = entries.first(where: { $0.suffix == suffix }) else { return [] }
        return entry.positions.prefix(3).map { p in
            ChordPosition(frets: p.frets, fingers: p.fingers, baseFret: p.baseFret, barres: p.barres)
        }
    }

    // MARK: - Private helpers

    private static func chordNameToKeySuffix(_ chord: String) -> (key: String, suffix: String)? {
        guard !chord.isEmpty, chord != "N", chord != "-" else { return nil }

        var normalized = chord

        // Strip slash bass note (e.g. "G/B" -> "G")
        if let slashIdx = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIdx])
        }

        // Extract root: 2 chars if second char is # or b, else 1 char
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

        // Normalize enharmonic equivalents
        let normalizedRoot = enharmonic[root] ?? root

        guard dbKeys.contains(normalizedRoot) else { return nil }
        guard let mappedSuffix = suffixMap[quality] else { return nil }

        return (normalizedRoot, mappedSuffix)
    }
}
