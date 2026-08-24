import Testing
import Foundation
@testable import Siyahamba

@MainActor
struct ImportViewModelTests {

    // MARK: - Helpers

    func makeViewModel(
        mockClient: MockImportAPIClient = MockImportAPIClient(),
        authToken: String? = nil
    ) throws -> (ImportViewModel, MockImportAPIClient, LibraryStore) {
        let cacheManager = try CacheManager()
        let libraryStore = LibraryStore(cacheManager: cacheManager)
        let authProvider = MockAuthTokenProvider(token: authToken)

        let viewModel = ImportViewModel(
            apiClient: mockClient,
            cacheManager: cacheManager,
            libraryStore: libraryStore,
            authViewModel: authProvider
        )
        return (viewModel, mockClient, libraryStore)
    }

    // MARK: - Cache Hit Tests

    @Test func cacheHitFile() async throws {
        let mockClient = MockImportAPIClient()
        let (viewModel, _, libraryStore) = try makeViewModel(mockClient: mockClient)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_cache_hit_\(UUID().uuidString).mp3")
        let fakeAudioData = Data(repeating: 0xAA, count: 1024)
        try fakeAudioData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let cacheManager = try CacheManager()
        let hash = try await cacheManager.sha256(of: tempFile)

        let existingEntry = SongEntry(
            id: UUID(), title: "Existing", artist: nil, duration: 30,
            sourceURL: nil, fileName: "test.mp3", sourceHash: hash, addedAt: Date()
        )
        await libraryStore.addSong(existingEntry)

        viewModel.startFileImport(from: tempFile)
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(viewModel.phase == .ready(cached: true))
        let callCount = await mockClient.uploadAudioCallCount
        #expect(callCount == 0)
    }

    @Test func convertedYouTubeDuplicateUsesCanonicalURL() async throws {
        let (viewModel, mockClient, libraryStore) = try makeViewModel()
        let existingEntry = SongEntry(
            id: UUID(), title: "Cached YT Song", artist: nil, duration: 210,
            sourceURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", fileName: nil,
            sourceHash: "existing", addedAt: Date()
        )
        await libraryStore.addSong(existingEntry)
        let result = try makeYouTubeConversionResult(url: "https://youtu.be/dQw4w9WgXcQ")

        let duplicate = viewModel.collectYouTubeConversion(result)

        #expect(duplicate?.id == existingEntry.id)
        #expect(viewModel.pendingItems.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: result.fileURL.path))
        let callCount = await mockClient.uploadAudioCallCount
        #expect(callCount == 0)
    }

    @Test func convertedYouTubeCancellationCleansTemporaryFile() throws {
        let (viewModel, _, _) = try makeViewModel()
        let result = try makeYouTubeConversionResult()

        #expect(viewModel.collectYouTubeConversion(result) == nil)
        #expect(viewModel.pendingItems.first?.title == "Vídeo de prueba")
        viewModel.cancelPending()

        #expect(!FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    @Test func convertedYouTubeRemainsUntilUploadAndStoresFullURL() async throws {
        let mockClient = MockImportAPIClient()
        await mockClient.setPollResult(.failure(APIError.processingFailed("fallo esperado")))
        let (viewModel, _, _) = try makeViewModel(mockClient: mockClient, authToken: "test-token")
        let result = try makeYouTubeConversionResult()

        #expect(viewModel.collectYouTubeConversion(result) == nil)
        let pending = try #require(viewModel.pendingItems.first)
        #expect(pending.originalURL?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))

        viewModel.confirmImport()
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(!FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    private func makeYouTubeConversionResult(
        url: String = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    ) throws -> YouTubeConversionResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("video.mp3")
        try Data(repeating: 0xAB, count: 512).write(to: fileURL)
        return YouTubeConversionResult(
            fileURL: fileURL,
            metadata: YouTubeVideoMetadata(id: "dQw4w9WgXcQ", title: "Vídeo de prueba", duration: 30),
            sourceURL: try YouTubeURL(url: #require(URL(string: url))).canonicalURL
        )
    }

    // MARK: - Error Handling

    @Test func uploadNetworkError() async throws {
        let mockClient = MockImportAPIClient()
        await mockClient.setUploadAudioResult(.failure(APIError.httpError(500)))
        let (viewModel, _, _) = try makeViewModel(mockClient: mockClient, authToken: "test-token")

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_upload_error_\(UUID().uuidString).mp3")
        try Data(repeating: 0xBB, count: 512).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        viewModel.startFileImport(from: tempFile)
        try await Task.sleep(nanoseconds: 500_000_000)

        if case .error = viewModel.phase { } else {
            Issue.record("Expected .error phase, got \(viewModel.phase)")
        }
    }

    @Test func pollError() async throws {
        let mockClient = MockImportAPIClient()
        await mockClient.setPollResult(.failure(APIError.processingFailed("stem separation failed")))
        let (viewModel, _, _) = try makeViewModel(mockClient: mockClient, authToken: "test-token")

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_poll_error_\(UUID().uuidString).mp3")
        try Data(repeating: 0xCC, count: 512).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        viewModel.startFileImport(from: tempFile)
        try await Task.sleep(nanoseconds: 500_000_000)

        if case .error(let msg) = viewModel.phase {
            #expect(msg.contains("stem separation"))
        } else {
            Issue.record("Expected .error phase, got \(viewModel.phase)")
        }
    }

    // MARK: - Cancel

    @Test func cancelReturnsToIdle() async throws {
        let mockClient = MockImportAPIClient()
        let (viewModel, _, _) = try makeViewModel(mockClient: mockClient)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_cancel_\(UUID().uuidString).mp3")
        try Data(repeating: 0xDD, count: 512).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        viewModel.startFileImport(from: tempFile)
        viewModel.cancel()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(viewModel.phase == .idle)
    }
}
