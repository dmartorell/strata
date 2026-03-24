import Foundation
import Observation
import ZIPFoundation

@Observable
@MainActor
final class ImportViewModel {
    private(set) var phase: ImportPhase = .idle
    private(set) var isProcessing: Bool = false

    var queueCount: Int { queue.count }
    var pendingItems: [PendingImportItem] = []

    private let apiClient: any ImportAPIClientProtocol
    private let cacheManager: CacheManager
    private let libraryStore: LibraryStore
    private var authViewModel: any AuthTokenProviderProtocol
    private var currentTask: Task<Void, Never>?
    private var placeholderID: UUID?
    private var queue: [QueueItem] = []

    init(apiClient: any ImportAPIClientProtocol = APIClient(), cacheManager: CacheManager, libraryStore: LibraryStore, authViewModel: any AuthTokenProviderProtocol) {
        self.apiClient = apiClient
        self.cacheManager = cacheManager
        self.libraryStore = libraryStore
        self.authViewModel = authViewModel
    }

    func startFileImport(from fileURL: URL, originalURL: URL? = nil, artist: String? = nil, title: String? = nil) {
        Task {
            await enqueueFileImport(fileURL: fileURL, originalURL: originalURL, artist: artist, title: title)
        }
    }

    func collectPendingFiles(_ files: [(fileURL: URL, originalURL: URL?)]) {
        pendingItems = files.map { file in
            let parsed = SongEntry.parseArtistAndTitle(from: file.fileURL.lastPathComponent)
            return PendingImportItem(
                fileURL: file.fileURL,
                originalURL: file.originalURL,
                artist: parsed.artist ?? "",
                title: parsed.title
            )
        }
    }

    func confirmImport() {
        let items = pendingItems
        pendingItems = []
        for item in items {
            startFileImport(from: item.fileURL, originalURL: item.originalURL, artist: item.artist, title: item.title)
        }
    }

    func cancelPending() {
        pendingItems = []
    }

    func dismissStatus() {
        if case .ready = phase { phase = .idle }
        if case .error = phase { phase = .idle }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil

        if let pid = placeholderID {
            libraryStore.removePlaceholder(id: pid)
            placeholderID = nil
        }
        for item in queue {
            libraryStore.removePlaceholder(id: item.placeholderID)
        }
        queue.removeAll()
        isProcessing = false
        phase = .idle
    }

    // MARK: - Private

    private func enqueueFileImport(fileURL: URL, originalURL: URL?, artist: String?, title: String?) async {
        do {
            let hash = try await cacheManager.sha256(of: fileURL)

            if libraryStore.isCached(sourceHash: hash) {
                if !isProcessing {
                    phase = .ready(cached: true)
                }
                return
            }

            let status: ImportStatus = isProcessing ? .queued : .active
            let placeholder = SongEntry.placeholder(
                fileName: fileURL.lastPathComponent,
                sourceHash: hash,
                importStatus: status,
                overrideArtist: artist,
                overrideTitle: title
            )
            libraryStore.addPlaceholder(placeholder)

            let item = QueueItem(
                fileURL: fileURL,
                originalURL: originalURL,
                placeholderID: placeholder.id,
                sourceHash: hash,
                artist: artist,
                title: title
            )
            queue.append(item)

            if !isProcessing {
                processNextInQueue()
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func processNextInQueue() {
        guard !queue.isEmpty else {
            isProcessing = false
            Task {
                try? await Task.sleep(for: .seconds(5))
                if case .ready = phase { phase = .idle }
            }
            return
        }

        isProcessing = true
        let item = queue.removeFirst()

        libraryStore.updatePlaceholderStatus(id: item.placeholderID, status: .active)
        placeholderID = item.placeholderID

        currentTask = Task {
            await runFileImport(item: item)
            processNextInQueue()
        }
    }

    private func runFileImport(item: QueueItem) async {
        do {
            phase = .validating
            try Task.checkCancellation()

            guard let token = authViewModel.token else {
                if let pid = placeholderID { libraryStore.removePlaceholder(id: pid); placeholderID = nil }
                phase = .error("No hay sesión activa")
                return
            }

            phase = .uploading
            try Task.checkCancellation()

            let fileData = try Data(contentsOf: item.fileURL)
            let mimeType = audioMimeType(for: item.fileURL)
            let jobId = try await apiClient.uploadAudio(
                fileData: fileData,
                fileName: item.fileURL.lastPathComponent,
                mimeType: mimeType,
                token: token
            )

            try await pollAndFinalize(
                jobId: jobId,
                sourceHash: item.sourceHash,
                displayName: item.fileURL.lastPathComponent,
                sourceURL: item.originalURL?.path,
                fileName: item.fileURL.lastPathComponent,
                overrideArtist: item.artist,
                overrideTitle: item.title
            )
        } catch let error as APIError where error == .httpError(429) {
            if let pid = placeholderID { libraryStore.removePlaceholder(id: pid); placeholderID = nil }
            phase = .error("Limite mensual de procesamiento alcanzado. Puedes seguir reproduciendo canciones ya procesadas.")
        } catch is CancellationError {
            if let pid = placeholderID { libraryStore.removePlaceholder(id: pid); placeholderID = nil }
            phase = .idle
        } catch {
            if let pid = placeholderID { libraryStore.removePlaceholder(id: pid); placeholderID = nil }
            phase = .error(error.localizedDescription)
        }
    }

    private func pollAndFinalize(
        jobId: String,
        sourceHash: String,
        displayName: String,
        sourceURL: String?,
        fileName: String?,
        overrideArtist: String?,
        overrideTitle: String?
    ) async throws {
        phase = .processing(stage: "queued")
        try Task.checkCancellation()

        let jobResult = try await apiClient.pollJobStatus(jobId: jobId, token: authViewModel.token ?? "") { [weak self] stage in
            Task { @MainActor in self?.phase = .processing(stage: stage) }
        }

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
                fileName: fileName,
                overrideArtist: overrideArtist,
                overrideTitle: overrideTitle
            )
        }.value

        try await cacheManager.materializeSong(id: songEntry.id, from: tempDir)
        if let pid = placeholderID {
            await libraryStore.replacePlaceholder(id: pid, with: songEntry)
            placeholderID = nil
        } else {
            await libraryStore.addSong(songEntry)
        }
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

// MARK: - QueueItem

private struct QueueItem {
    let fileURL: URL
    let originalURL: URL?
    let placeholderID: UUID
    let sourceHash: String
    let artist: String?
    let title: String?
}

// MARK: - ZIP Extraction (nonisolated helper)

private func extractToTemp(
    zipData: Data,
    sourceHash: String,
    sourceURL: String?,
    fileName: String?,
    overrideArtist: String?,
    overrideTitle: String?
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

    var inferredKey: String?
    let chordsURL = tempDir.appendingPathComponent("chords.json")
    if let chordsData = try? Data(contentsOf: chordsURL) {
        let decoder = JSONDecoder()
        let chords: [ChordEntry] = (try? decoder.decode(ChordsFile.self, from: chordsData).chords)
            ?? (try? decoder.decode([ChordEntry].self, from: chordsData))
            ?? []
        inferredKey = ChordTransposer.inferKey(from: chords)
    }

    let parsed = fileName.map(SongEntry.parseArtistAndTitle)

    let resolvedTitle: String
    if let override = overrideTitle, !override.isEmpty {
        resolvedTitle = override
    } else {
        resolvedTitle = parsed?.title ?? metadata.title
    }

    let resolvedArtist: String?
    if let override = overrideArtist, !override.isEmpty {
        resolvedArtist = override
    } else {
        resolvedArtist = metadata.artist ?? parsed?.artist
    }

    let songID = UUID()
    let entry = SongEntry(
        id: songID,
        title: resolvedTitle,
        artist: resolvedArtist,
        duration: metadata.durationSeconds ?? 0,
        sourceURL: sourceURL,
        fileName: fileName,
        sourceHash: sourceHash,
        addedAt: Date(),
        key: inferredKey
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
