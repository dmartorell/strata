import Foundation

struct PendingImportItem: Identifiable {
    let id = UUID()
    let fileURL: URL
    let originalURL: URL?
    var artist: String
    var title: String
}
