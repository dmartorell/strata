import Foundation

struct LyricsFile: Decodable, Sendable {
    let language: String
    let segments: [LyricLine]
}

struct LyricLine: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Double
    let end: Double
    let text: String
    let words: [LyricWord]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
        self.text = try container.decode(String.self, forKey: .text)
        self.words = try container.decode([LyricWord].self, forKey: .words)
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, text, words
    }

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.start == rhs.start && lhs.text == rhs.text
    }
}

struct LyricWord: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let word: String
    let start: Double
    let end: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.word = try container.decode(String.self, forKey: .word)
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
    }

    private enum CodingKeys: String, CodingKey {
        case word, start, end
    }

    static func == (lhs: LyricWord, rhs: LyricWord) -> Bool {
        lhs.start == rhs.start && lhs.word == rhs.word
    }
}
