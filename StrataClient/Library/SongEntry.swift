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
}
