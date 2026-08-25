import Foundation
import Testing
@testable import Siyahamba

private struct StubProcessExecutor: YouTubeProcessExecuting {
    let result: YouTubeProcessResult

    func run(executable: URL, arguments: [String]) async throws -> YouTubeProcessResult {
        result
    }
}

private actor RecordingProcessExecutor: YouTubeProcessExecuting {
    private let result: YouTubeProcessResult
    private(set) var arguments: [[String]] = []

    init(result: YouTubeProcessResult) {
        self.result = result
    }

    func run(executable: URL, arguments: [String]) async throws -> YouTubeProcessResult {
        self.arguments.append(arguments)
        return result
    }
}

struct YouTubeConverterTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ"
    ])
    func normalizesIndividualVideoURLs(rawURL: String) throws {
        let parsed = try YouTubeURL(url: #require(URL(string: rawURL)))

        #expect(parsed.videoID == "dQw4w9WgXcQ")
        #expect(parsed.canonicalURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test("Obtiene metadatos de un vídeo admitido")
    func inspectsVideoMetadata() async throws {
        let executable = URL(fileURLWithPath: "/tmp/yt-dlp")
        let locator = YouTubeToolLocator(resourceURL: { _ in executable }, isExecutable: { _ in true })
        let data = #"{"id":"dQw4w9WgXcQ","title":"Canción","duration":212}"#.data(using: .utf8)!
        let converter = YouTubeConverter(
            toolLocator: locator,
            processExecutor: StubProcessExecutor(result: .init(status: 0, standardOutput: data, standardError: Data()))
        )
        let request = YouTubeConversionRequest(
            url: try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")), format: .mp3, quality: .standard
        )

        let metadata = try await converter.inspect(request)

        #expect(metadata.title == "Canción")
        #expect(metadata.duration == 212)
    }

    @Test("Indica a yt-dlp el runtime Deno empaquetado")
    func usesBundledDenoRuntime() async throws {
        let ytDlp = URL(fileURLWithPath: "/tmp/yt-dlp")
        let deno = URL(fileURLWithPath: "/tmp/deno-arm64")
        let locator = YouTubeToolLocator(
            resourceURL: { name in name == "deno-arm64" ? deno : ytDlp },
            isExecutable: { _ in true }
        )
        let data = #"{"id":"dQw4w9WgXcQ","title":"Canción","duration":212}"#.data(using: .utf8)!
        let executor = RecordingProcessExecutor(
            result: .init(status: 0, standardOutput: data, standardError: Data())
        )
        let converter = YouTubeConverter(toolLocator: locator, processExecutor: executor)
        let request = YouTubeConversionRequest(
            url: try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")), format: .mp3, quality: .standard
        )

        _ = try await converter.inspect(request)

        #expect(await executor.arguments == [[
            "--js-runtimes", "deno:/tmp/deno-arm64",
            "--extractor-args", "youtube:player_client=android",
            "--no-playlist", "--dump-single-json", "--skip-download",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        ]])
    }

    @Test("Rechaza vídeos superiores a diez minutos")
    func rejectsLongVideo() async throws {
        let executable = URL(fileURLWithPath: "/tmp/yt-dlp")
        let locator = YouTubeToolLocator(resourceURL: { _ in executable }, isExecutable: { _ in true })
        let data = #"{"id":"dQw4w9WgXcQ","title":"Sesión larga","duration":601}"#.data(using: .utf8)!
        let converter = YouTubeConverter(
            toolLocator: locator,
            processExecutor: StubProcessExecutor(result: .init(status: 0, standardOutput: data, standardError: Data()))
        )
        let request = YouTubeConversionRequest(
            url: try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")), format: .m4a, quality: .standard
        )

        await #expect(throws: YouTubeConverterError.videoTooLong) {
            try await converter.inspect(request)
        }
    }

    @Test("Traduce errores de yt-dlp a vídeo no disponible")
    func rejectsUnavailableVideo() async throws {
        let executable = URL(fileURLWithPath: "/tmp/yt-dlp")
        let locator = YouTubeToolLocator(resourceURL: { _ in executable }, isExecutable: { _ in true })
        let converter = YouTubeConverter(
            toolLocator: locator,
            processExecutor: StubProcessExecutor(result: .init(status: 1, standardOutput: Data(), standardError: Data("private".utf8)))
        )
        let request = YouTubeConversionRequest(
            url: try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")), format: .mp3, quality: .standard
        )

        await #expect(throws: YouTubeConverterError.unsupportedVideo) {
            try await converter.inspect(request)
        }
    }

    @Test func rejectsPlaylist() throws {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123"))
        #expect(throws: YouTubeConverterError.playlistNotSupported) {
            try YouTubeURL(url: url)
        }
    }

    @Test(arguments: ["https://example.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/channel/test"])
    func rejectsUnsupportedURLs(rawURL: String) throws {
        #expect(throws: YouTubeConverterError.invalidURL) {
            try YouTubeURL(url: #require(URL(string: rawURL)))
        }
    }
}
