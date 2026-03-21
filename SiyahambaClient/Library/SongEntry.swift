import Foundation

struct SongEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String?
    let duration: Double
    let sourceURL: String?
    let fileName: String?
    let sourceHash: String
    let addedAt: Date
    var pitchOffset: Int?
    var key: String?
    var displayMode: DisplayMode?
    var isPlaceholder: Bool?

    enum DisplayMode: String, Codable, Sendable {
        case waveforms
        case lyrics
        case lyricsAndChords
        case chords
    }

    init(
        id: UUID,
        title: String,
        artist: String? = nil,
        duration: Double,
        sourceURL: String? = nil,
        fileName: String? = nil,
        sourceHash: String,
        addedAt: Date,
        pitchOffset: Int? = nil,
        key: String? = nil,
        displayMode: DisplayMode? = nil,
        isPlaceholder: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.sourceHash = sourceHash
        self.addedAt = addedAt
        self.pitchOffset = pitchOffset
        self.key = key
        self.displayMode = displayMode
        self.isPlaceholder = isPlaceholder
    }

    static func placeholder(fileName: String, sourceHash: String) -> SongEntry {
        let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return SongEntry(
            id: UUID(),
            title: nameWithoutExtension,
            artist: nil,
            duration: 0,
            sourceURL: nil,
            fileName: fileName,
            sourceHash: sourceHash,
            addedAt: Date(),
            isPlaceholder: true
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decodeIfPresent(String.self, forKey: .artist)
        self.duration = try container.decode(Double.self, forKey: .duration)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        self.sourceHash = try container.decode(String.self, forKey: .sourceHash)
        self.addedAt = try container.decode(Date.self, forKey: .addedAt)
        self.pitchOffset = try container.decodeIfPresent(Int.self, forKey: .pitchOffset)
        self.key = try container.decodeIfPresent(String.self, forKey: .key)
        self.displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode)
        self.isPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isPlaceholder)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, duration, sourceURL, fileName, sourceHash, addedAt, pitchOffset, key, displayMode, isPlaceholder
    }
}
