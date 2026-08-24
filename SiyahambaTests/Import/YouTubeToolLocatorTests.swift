import Foundation
import Testing
@testable import Siyahamba

struct YouTubeToolLocatorTests {
    @Test("Selecciona FFmpeg arm64")
    func selectsArm64FFmpeg() throws {
        let arm64URL = URL(fileURLWithPath: "/tmp/ffmpeg-arm64")
        let locator = YouTubeToolLocator(
            resourceURL: { name in name == "ffmpeg-arm64" ? arm64URL : nil },
            isExecutable: { $0 == arm64URL }
        )

        let url = try locator.url(for: .ffmpeg, architecture: .arm64)

        #expect(url == arm64URL)
    }

    @Test("Selecciona FFmpeg x86_64")
    func selectsIntelFFmpeg() throws {
        let intelURL = URL(fileURLWithPath: "/tmp/ffmpeg-x86_64")
        let locator = YouTubeToolLocator(
            resourceURL: { name in name == "ffmpeg-x86_64" ? intelURL : nil },
            isExecutable: { $0 == intelURL }
        )

        let url = try locator.url(for: .ffmpeg, architecture: .x86_64)

        #expect(url == intelURL)
    }

    @Test("Falla con error localizado si falta una herramienta")
    func reportsMissingTool() {
        let locator = YouTubeToolLocator(resourceURL: { _ in nil })

        #expect(throws: YouTubeToolLocatorError.missingResource("yt-dlp")) {
            try locator.url(for: .ytDlp)
        }
    }

    @Test("Rechaza recursos sin permiso de ejecución")
    func rejectsNonExecutableTool() {
        let url = URL(fileURLWithPath: "/tmp/yt-dlp")
        let locator = YouTubeToolLocator(resourceURL: { _ in url }, isExecutable: { _ in false })

        #expect(throws: YouTubeToolLocatorError.notExecutable(url)) {
            try locator.url(for: .ytDlp)
        }
    }
}
