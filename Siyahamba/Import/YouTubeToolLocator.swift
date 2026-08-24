import Foundation

enum YouTubeTool: Sendable {
    case ytDlp
    case ffmpeg
}

enum YouTubeToolArchitecture: Sendable {
    case arm64
    case x86_64

    static var current: Self {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }
}

enum YouTubeToolLocatorError: LocalizedError, Equatable {
    case missingResource(String)
    case notExecutable(URL)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "No se encuentra la herramienta de conversión \(name). Reinstala Siyahamba."
        case .notExecutable(let url):
            "La herramienta de conversión \(url.lastPathComponent) no se puede ejecutar. Reinstala Siyahamba."
        }
    }
}

struct YouTubeToolLocator: Sendable {
    typealias ResourceLookup = @Sendable (String) -> URL?
    typealias ExecutableCheck = @Sendable (URL) -> Bool

    private let resourceURL: ResourceLookup
    private let isExecutable: ExecutableCheck

    init(
        resourceURL: @escaping ResourceLookup,
        isExecutable: @escaping ExecutableCheck = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
        self.resourceURL = resourceURL
        self.isExecutable = isExecutable
    }

    static let live = YouTubeToolLocator(resourceURL: { name in
        guard let toolsBundle = Bundle.main.url(forResource: "YouTubeTools", withExtension: "bundle") else {
            return nil
        }
        let relativePath = name == "yt-dlp" ? "yt-dlp/yt-dlp_macos" : name
        let url = toolsBundle.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    })

    func url(for tool: YouTubeTool, architecture: YouTubeToolArchitecture = .current) throws -> URL {
        let name: String
        switch tool {
        case .ytDlp:
            name = "yt-dlp"
        case .ffmpeg:
            name = switch architecture {
            case .arm64: "ffmpeg-arm64"
            case .x86_64: "ffmpeg-x86_64"
            }
        }

        guard let url = resourceURL(name) else {
            throw YouTubeToolLocatorError.missingResource(name)
        }
        guard isExecutable(url) else {
            throw YouTubeToolLocatorError.notExecutable(url)
        }
        return url
    }
}
