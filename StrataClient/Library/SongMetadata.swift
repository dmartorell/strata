import Foundation

struct SongMetadata: Codable, Sendable {
    let title: String
    let artist: String?
    let durationSeconds: Double?
    let sampleRate: Int?
    let sourceType: String?
    let processedAt: String?
    let originalFilename: String?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case durationSeconds = "duration_seconds"
        case sampleRate = "sample_rate"
        case sourceType = "source_type"
        case processedAt = "processed_at"
        case originalFilename = "original_filename"
    }
}
