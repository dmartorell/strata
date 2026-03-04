import Foundation

enum ChordTransposer {
    static let sharpRoots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatRoots  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    private static var allRoots: [String] {
        (sharpRoots + flatRoots)
            .removingDuplicates()
            .sorted { $0.count > $1.count }
    }

    static func transpose(_ chord: String, semitones: Int) -> String {
        guard semitones != 0 else { return chord }

        let roots = allRoots
        guard let root = roots.first(where: { chord.hasPrefix($0) }) else {
            return chord
        }

        let suffix = String(chord.dropFirst(root.count))
        let scale = semitones > 0 ? sharpRoots : flatRoots

        let index = (sharpRoots.firstIndex(of: root) ?? flatRoots.firstIndex(of: root) ?? 0)
        let newIndex = ((index + semitones) % 12 + 12) % 12
        let newRoot = scale[newIndex]

        return newRoot + suffix
    }

    static func inferKey(from chords: [ChordEntry]) -> String? {
        guard !chords.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for entry in chords {
            let root = rootOnly(entry.chord)
            counts[root, default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func rootOnly(_ chord: String) -> String {
        let roots = allRoots
        return roots.first(where: { chord.hasPrefix($0) }) ?? chord
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
