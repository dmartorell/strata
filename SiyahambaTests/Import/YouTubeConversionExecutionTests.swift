import Foundation
import Testing
@testable import Siyahamba

private actor QueuedProcessExecutor: YouTubeProcessExecuting {
    private var results: [YouTubeProcessResult]

    init(_ results: [YouTubeProcessResult]) { self.results = results }

    func run(executable: URL, arguments: [String]) async throws -> YouTubeProcessResult {
        results.removeFirst()
    }
}

struct YouTubeConversionExecutionTests {
    @Test("Convierte y devuelve el temporal resultante")
    func convertsAudio() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("yt-conversion-\(UUID()).mp3")
        try Data(repeating: 1, count: 128).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = Data(#"{"id":"dQw4w9WgXcQ","title":"Canción","duration":120}"#.utf8)
        let executor = QueuedProcessExecutor([
            .init(status: 0, standardOutput: metadata, standardError: Data()),
            .init(status: 0, standardOutput: Data("\(file.path)\n".utf8), standardError: Data())
        ])
        let executable = URL(fileURLWithPath: "/tmp/tool")
        let converter = YouTubeConverter(
            toolLocator: .init(resourceURL: { _ in executable }, isExecutable: { _ in true }),
            processExecutor: executor
        )
        let request = YouTubeConversionRequest(url: try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")), format: .mp3, quality: .standard)

        let result = try await converter.convert(request)

        #expect(result.fileURL == file)
        #expect(result.metadata.title == "Canción")
    }

    @Test("Cancelar termina el proceso hijo")
    func cancellationTerminatesProcess() async throws {
        let executor = YouTubeProcessExecutor()
        let task = Task {
            try await executor.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 10"])
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Rechaza resultados superiores a 50 MB")
    func rejectsLargeOutput() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("yt-large-\(UUID()).mp3")
        try Data(repeating: 0, count: 50 * 1024 * 1024 + 1).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = Data(#"{"id":"dQw4w9WgXcQ","title":"Larga","duration":120}"#.utf8)
        let converter = YouTubeConverter(
            toolLocator: .init(resourceURL: { _ in URL(fileURLWithPath: "/tmp/tool") }, isExecutable: { _ in true }),
            processExecutor: QueuedProcessExecutor([
                .init(status: 0, standardOutput: metadata, standardError: Data()),
                .init(status: 0, standardOutput: Data("\(file.path)\n".utf8), standardError: Data())
            ])
        )
        let request = YouTubeConversionRequest(url: try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")), format: .mp3, quality: .high)

        await #expect(throws: YouTubeConverterError.outputTooLarge) {
            try await converter.convert(request)
        }
    }
}
