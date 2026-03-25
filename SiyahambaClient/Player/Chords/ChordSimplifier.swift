import Foundation

enum DifficultyLevel: String, CaseIterable {
    case principiante = "Principiante"
    case intermedio = "Intermedio"
    case avanzado = "Avanzado"
}

enum ChordSimplifier {

    private static let beginnerMap: [String: String] = [
        "7": "", "maj7": "", "m7": "m", "dim7": "dim", "m7b5": "m",
        "aug7": "aug", "mmaj7": "m",
        "9": "", "maj9": "", "m9": "m", "add9": "",
        "sus2": "", "sus4": "",
        "6": "", "m6": "m",
        "5": ""
    ]

    private static let intermediateMap: [String: String] = [
        "9": "7", "maj9": "maj7", "m9": "m7",
        "add9": "", "6": "", "m6": "m",
        "m7b5": "m7", "mmaj7": "m7", "aug7": "7",
        "5": ""
    ]

    static func simplify(_ chord: String, level: DifficultyLevel) -> String {
        guard level != .avanzado else { return chord }
        guard !chord.isEmpty, chord != "N", chord != "-" else { return chord }

        var normalized = chord
        if let slashIdx = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIdx])
        }

        let root: String
        let suffix: String
        if normalized.count >= 2 {
            let secondChar = normalized[normalized.index(normalized.startIndex, offsetBy: 1)]
            if secondChar == "#" || secondChar == "b" {
                root = String(normalized.prefix(2))
                suffix = String(normalized.dropFirst(2))
            } else {
                root = String(normalized.prefix(1))
                suffix = String(normalized.dropFirst(1))
            }
        } else {
            root = normalized
            suffix = ""
        }

        let map = level == .principiante ? beginnerMap : intermediateMap
        let newSuffix = map[suffix] ?? suffix
        return root + newSuffix
    }
}
