import Foundation
import Testing
@testable import Siyahamba

private struct FakeYouTubeConverter: YouTubeConverting {
    let result: Result<YouTubeConversionResult, Error>

    func inspect(_ request: YouTubeConversionRequest) async throws -> YouTubeVideoMetadata {
        try result.get().metadata
    }

    func convert(_ request: YouTubeConversionRequest) async throws -> YouTubeConversionResult {
        try result.get()
    }

    func convert(
        _ request: YouTubeConversionRequest,
        onProgress: @escaping @Sendable (YouTubeConversionProgress) -> Void
    ) async throws -> YouTubeConversionResult {
        onProgress(.init(phase: .downloading, fractionCompleted: 0.5))
        onProgress(.init(phase: .converting, fractionCompleted: 1))
        return try result.get()
    }
}

@MainActor
struct YouTubeConversionSheetTests {
    @Test func defaultsUseMP3At192Kbps() throws {
        let viewModel = try makeViewModel()

        #expect(viewModel.format == .mp3)
        #expect(viewModel.quality == .standard)
        #expect(!viewModel.isConverting)
    }

    @Test func failedConversionKeepsFormValuesAndAllowsRetry() async throws {
        let converter = FakeYouTubeConverter(result: .failure(YouTubeConverterError.videoTooLong))
        let viewModel = try makeViewModel(converter: converter)
        viewModel.urlString = "https://youtu.be/dQw4w9WgXcQ"
        viewModel.format = .m4a
        viewModel.quality = .high

        viewModel.convert()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(viewModel.errorMessage == YouTubeConverterError.videoTooLong.localizedDescription)
        #expect(viewModel.urlString == "https://youtu.be/dQw4w9WgXcQ")
        #expect(viewModel.format == .m4a)
        #expect(viewModel.quality == .high)
    }

    @Test func successfulConversionUpdatesProgressAndHandsOffToMetadataConfirmation() async throws {
        let result = try makeResult()
        defer { try? FileManager.default.removeItem(at: result.fileURL.deletingLastPathComponent()) }
        let converter = FakeYouTubeConverter(result: .success(result))
        let viewModel = try makeViewModel(converter: converter)
        viewModel.urlString = result.sourceURL.absoluteString

        viewModel.convert()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(viewModel.progress == 1)
        #expect(viewModel.progressLabel == "Convirtiendo")
        #expect(viewModel.completedSong == nil)
        #expect(viewModel.state == .completed)
        #expect(viewModel.errorMessage == nil)
    }

    private func makeViewModel(converter: any YouTubeConverting = FakeYouTubeConverter(result: .failure(YouTubeConverterError.unsupportedVideo))) throws -> YouTubeConversionViewModel {
        let cacheManager = try CacheManager()
        let libraryStore = LibraryStore(cacheManager: cacheManager)
        let importViewModel = ImportViewModel(
            apiClient: MockImportAPIClient(),
            cacheManager: cacheManager,
            libraryStore: libraryStore,
            authViewModel: MockAuthTokenProvider()
        )
        return YouTubeConversionViewModel(converter: converter, importViewModel: importViewModel)
    }

    private func makeResult() throws -> YouTubeConversionResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("video.mp3")
        try Data(repeating: 0xAB, count: 512).write(to: fileURL)
        return YouTubeConversionResult(
            fileURL: fileURL,
            metadata: YouTubeVideoMetadata(id: "dQw4w9WgXcQ", title: "Vídeo de prueba", duration: 30),
            sourceURL: try YouTubeURL(url: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ"))).canonicalURL
        )
    }
}
