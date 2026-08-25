import Foundation

struct PendingImportItem: Identifiable {
    let id = UUID()
    let fileURL: URL
    let originalURL: URL?
    let cleanup: (() -> Void)?
    var artist: String
    var title: String

    func cleanUpTemporaryFile() {
        cleanup?()
    }
}
