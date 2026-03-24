import Foundation

enum ImportStatus: String, Codable, Sendable {
    case active
    case queued
}

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
    var lyricsOffset: Double?
    var key: String?
    var displayMode: DisplayMode?
    var isPlaceholder: Bool?
    var importStatus: ImportStatus?

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
        lyricsOffset: Double? = nil,
        key: String? = nil,
        displayMode: DisplayMode? = nil,
        isPlaceholder: Bool? = nil,
        importStatus: ImportStatus? = nil
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
        self.lyricsOffset = lyricsOffset
        self.key = key
        self.displayMode = displayMode
        self.isPlaceholder = isPlaceholder
        self.importStatus = importStatus
    }

    static func parseArtistAndTitle(from fileName: String) -> (artist: String?, title: String) {
        let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let parts = nameWithoutExtension.split(separator: "-", maxSplits: 1)
        guard parts.count == 2 else {
            return (nil, nameWithoutExtension)
        }
        let artist = parts[0].trimmingCharacters(in: .whitespaces)
        let title = parts[1].trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else {
            return (nil, nameWithoutExtension)
        }
        return (artist, title)
    }

    static func placeholder(fileName: String, sourceHash: String, importStatus: ImportStatus = .active, overrideArtist: String? = nil, overrideTitle: String? = nil) -> SongEntry {
        let parsed = parseArtistAndTitle(from: fileName)
        let resolvedTitle = (overrideTitle.map { $0.isEmpty ? nil : $0 } ?? nil) ?? parsed.title
        let resolvedArtist = (overrideArtist.map { $0.isEmpty ? nil : $0 } ?? nil) ?? parsed.artist
        return SongEntry(
            id: UUID(),
            title: resolvedTitle,
            artist: resolvedArtist,
            duration: 0,
            sourceURL: nil,
            fileName: fileName,
            sourceHash: sourceHash,
            addedAt: Date(),
            isPlaceholder: true,
            importStatus: importStatus
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
        self.lyricsOffset = try container.decodeIfPresent(Double.self, forKey: .lyricsOffset)
        self.key = try container.decodeIfPresent(String.self, forKey: .key)
        self.displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode)
        self.isPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isPlaceholder)
        self.importStatus = try container.decodeIfPresent(ImportStatus.self, forKey: .importStatus)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, duration, sourceURL, fileName, sourceHash, addedAt, pitchOffset, lyricsOffset, key, displayMode, isPlaceholder, importStatus
    }
}
