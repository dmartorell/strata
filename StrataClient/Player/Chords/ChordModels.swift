import Foundation

struct ChordsFile: Decodable, Sendable {
    let chords: [ChordEntry]
}

struct ChordEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Double
    let end: Double?
    let chord: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decodeIfPresent(Double.self, forKey: .end)
        self.chord = try container.decode(String.self, forKey: .chord)
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, chord
    }

    static func == (lhs: ChordEntry, rhs: ChordEntry) -> Bool {
        lhs.start == rhs.start && lhs.chord == rhs.chord
    }
}
