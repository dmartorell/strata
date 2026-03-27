import Foundation

struct ChordsFile: Decodable, Sendable {
    let chords: [ChordEntry]
}

struct ChordPosition: Decodable, Sendable, Equatable {
    let frets: [Int]
    let fingers: [Int]
    let baseFret: Int
    let barres: [Int]
}

struct ChordEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Double
    var end: Double?
    let chord: String
    let fingerings: [ChordPosition]?

    init(id: UUID = UUID(), start: Double, end: Double? = nil, chord: String, fingerings: [ChordPosition]? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.chord = chord
        self.fingerings = fingerings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decodeIfPresent(Double.self, forKey: .end)
        self.chord = try container.decode(String.self, forKey: .chord)
        self.fingerings = try container.decodeIfPresent([ChordPosition].self, forKey: .fingerings)
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, chord, fingerings
    }

    static func == (lhs: ChordEntry, rhs: ChordEntry) -> Bool {
        lhs.start == rhs.start && lhs.chord == rhs.chord
    }
}
