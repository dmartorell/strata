import Foundation
import Observation
import ZIPFoundation

@Observable
@MainActor
final class ImportViewModel {
    private(set) var phase: ImportPhase = .idle

    private let apiClient: any ImportAPIClientProtocol
    private let cacheManager: CacheManager
    private let libraryStore: LibraryStore
    private var authViewModel: AuthViewModel
    private var currentTask: Task<Void, Never>?

    init(apiClient: any ImportAPIClientProtocol = APIClient(), cacheManager: CacheManager, libraryStore: LibraryStore, authViewModel: AuthViewModel) {
        self.apiClient = apiClient
        self.cacheManager = cacheManager
        self.libraryStore = libraryStore
        self.authViewModel = authViewModel
    }

    func startFileImport(from fileURL: URL) {
        cancelCurrentTask()
        currentTask = Task {
            await runFileImport(fileURL: fileURL)
        }
    }

    func startURLImport(urlString: String) {
        cancelCurrentTask()
        currentTask = Task {
            await runURLImport(urlString: urlString)
        }
    }

    func cancel() {
        cancelCurrentTask()
        phase = .idle
    }

    // MARK: - Private

    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func runFileImport(fileURL: URL) async {
        do {
            phase = .validating
            try Task.checkCancellation()

            let hash = try await cacheManager.sha256(of: fileURL)

            if libraryStore.isCached(sourceHash: hash) {
                phase = .ready(cached: true)
                return
            }

            guard let token = authViewModel.token else {
                phase = .error("No hay sesión activa")
                return
            }

            phase = .uploading
            try Task.checkCancellation()

            let fileData = try Data(contentsOf: fileURL)
            let mimeType = audioMimeType(for: fileURL)
            let jobId = try await apiClient.uploadAudio(
                fileData: fileData,
                fileName: fileURL.lastPathComponent,
                mimeType: mimeType,
                token: token
            )

            try await pollAndFinalize(
                jobId: jobId,
                sourceHash: hash,
                displayName: fileURL.deletingPathExtension().lastPathComponent,
                sourceURL: nil,
                fileName: fileURL.lastPathComponent
            )
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func runURLImport(urlString: String) async {
        do {
            phase = .validating
            try Task.checkCancellation()

            guard let videoID = await cacheManager.youtubeVideoID(from: urlString) else {
                phase = .error("URL de YouTube no válida")
                return
            }

            if libraryStore.isCached(sourceHash: videoID) {
                phase = .ready(cached: true)
                return
            }

            guard let token = authViewModel.token else {
                phase = .error("No hay sesión activa")
                return
            }

            phase = .uploading
            try Task.checkCancellation()

            let jobId = try await apiClient.uploadURL(urlString: urlString, token: token)

            try await pollAndFinalize(
                jobId: jobId,
                sourceHash: videoID,
                displayName: urlString,
                sourceURL: urlString,
                fileName: nil
            )
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func pollAndFinalize(
        jobId: String,
        sourceHash: String,
        displayName: String,
        sourceURL: String?,
        fileName: String?
    ) async throws {
        phase = .processing(stage: "queued")
        try Task.checkCancellation()

        let jobResult = try await apiClient.pollJobStatus(jobId: jobId, token: authViewModel.token ?? "")

        guard let zipData = jobResult.zipData else {
            throw ImportError.missingZipData
        }

        phase = .processing(stage: "extracting")
        try Task.checkCancellation()

        let (songEntry, tempDir) = try await Task.detached(priority: .userInitiated) {
            try extractToTemp(
                zipData: zipData,
                sourceHash: sourceHash,
                sourceURL: sourceURL,
                fileName: fileName
            )
        }.value

        try await cacheManager.materializeSong(id: songEntry.id, from: tempDir)
        await libraryStore.addSong(songEntry)
        phase = .ready(cached: false)
    }

    private func audioMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":  return "audio/mpeg"
        case "wav":  return "audio/wav"
        case "flac": return "audio/flac"
        case "m4a":  return "audio/mp4"
        default:     return "audio/mpeg"
        }
    }
}

// MARK: - ZIP Extraction (nonisolated helper)

private func extractToTemp(
    zipData: Data,
    sourceHash: String,
    sourceURL: String?,
    fileName: String?
) throws -> (SongEntry, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let archive = try Archive(data: zipData, accessMode: .read)
    for entry in archive {
        let destURL = tempDir.appendingPathComponent(entry.path)
        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        _ = try archive.extract(entry, to: destURL)
    }

    let metadataURL = tempDir.appendingPathComponent("metadata.json")
    let metadataData = try Data(contentsOf: metadataURL)
    let metadata = try JSONDecoder().decode(SongMetadata.self, from: metadataData)

    let songID = UUID()
    let entry = SongEntry(
        id: songID,
        title: metadata.title,
        artist: metadata.artist,
        duration: metadata.duration,
        sourceURL: sourceURL,
        fileName: fileName,
        sourceHash: sourceHash,
        addedAt: Date()
    )
    return (entry, tempDir)
}

// MARK: - ImportError

enum ImportError: LocalizedError {
    case missingZipData
    case invalidMetadata(String)

    var errorDescription: String? {
        switch self {
        case .missingZipData:         return "El servidor no devolvió el archivo ZIP"
        case .invalidMetadata(let m): return "Metadatos inválidos: \(m)"
        }
    }
}
