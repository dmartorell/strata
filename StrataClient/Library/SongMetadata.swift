import Foundation

struct SongMetadata: Codable, Sendable {
    let id: String
    let title: String
    let artist: String?
    let duration: Double
    let sourceURL: String?
    let fileName: String?
    let sourceHash: String
    let addedAt: String
}
