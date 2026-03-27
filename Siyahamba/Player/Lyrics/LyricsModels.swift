import Foundation

struct LyricsFile: Codable, Sendable {
    let language: String
    let segments: [LyricLine]
}

struct LyricLine: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Double
    let end: Double
    let text: String
    var words: [LyricWord]

    init(id: UUID = UUID(), start: Double, end: Double, text: String, words: [LyricWord]) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
        self.text = try container.decode(String.self, forKey: .text)
        self.words = try container.decode([LyricWord].self, forKey: .words)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(text, forKey: .text)
        try container.encode(words, forKey: .words)
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, text, words
    }

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.start == rhs.start && lhs.text == rhs.text
    }
}

struct LyricWord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let word: String
    let start: Double
    let end: Double

    init(id: UUID = UUID(), word: String, start: Double, end: Double) {
        self.id = id
        self.word = word
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.word = try container.decode(String.self, forKey: .word)
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }

    private enum CodingKeys: String, CodingKey {
        case word, start, end
    }

    static func == (lhs: LyricWord, rhs: LyricWord) -> Bool {
        lhs.start == rhs.start && lhs.word == rhs.word
    }
}
