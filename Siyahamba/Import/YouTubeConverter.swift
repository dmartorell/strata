import Foundation

enum YouTubeFormat: String, CaseIterable, Sendable {
    case mp3
    case m4a
}

enum YouTubeQuality: Int, CaseIterable, Sendable {
    case low = 128
    case standard = 192
    case high = 320
}

struct YouTubeConversionRequest: Sendable {
    let url: URL
    let format: YouTubeFormat
    let quality: YouTubeQuality
}

struct YouTubeVideoMetadata: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let duration: Double?
}

struct YouTubeConversionResult: Sendable {
    let fileURL: URL
    let metadata: YouTubeVideoMetadata
    let sourceURL: URL
}

enum YouTubeConversionPhase: Sendable {
    case downloading
    case converting
}

struct YouTubeConversionProgress: Sendable {
    let phase: YouTubeConversionPhase
    let fractionCompleted: Double
}

enum YouTubeConverterError: LocalizedError, Equatable {
    case invalidURL
    case playlistNotSupported
    case unsupportedVideo
    case videoTooLong
    case outputTooLarge
    case toolFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: "La URL debe ser un vídeo de YouTube válido."
        case .playlistNotSupported: "Las playlists no están permitidas. Selecciona un vídeo individual."
        case .unsupportedVideo: "El vídeo no está disponible. Prueba importando un archivo de audio local."
        case .videoTooLong: "El vídeo supera el límite de 10 minutos."
        case .outputTooLarge: "El audio convertido supera el límite de 50 MB."
        case .toolFailed(let details): "No se pudo convertir el vídeo. \(details)"
        case .cancelled: "La conversión se canceló."
        }
    }
}

protocol YouTubeConverting: Sendable {
    func inspect(_ request: YouTubeConversionRequest) async throws -> YouTubeVideoMetadata
    func convert(_ request: YouTubeConversionRequest) async throws -> YouTubeConversionResult
}

struct YouTubeConverter: YouTubeConverting {
    private let toolLocator: YouTubeToolLocator
    private let processExecutor: any YouTubeProcessExecuting

    init(
        toolLocator: YouTubeToolLocator = .live,
        processExecutor: any YouTubeProcessExecuting = YouTubeProcessExecutor()
    ) {
        self.toolLocator = toolLocator
        self.processExecutor = processExecutor
    }

    func inspect(_ request: YouTubeConversionRequest) async throws -> YouTubeVideoMetadata {
        let video = try YouTubeURL(url: request.url)
        let executable = try toolLocator.url(for: .ytDlp)
        let result = try await processExecutor.run(
            executable: executable,
            arguments: ["--no-playlist", "--dump-single-json", "--skip-download", video.canonicalURL.absoluteString]
        )
        guard result.status == 0 else {
            throw YouTubeConverterError.unsupportedVideo
        }
        let metadata: YouTubeVideoMetadata
        do {
            metadata = try JSONDecoder().decode(YouTubeVideoMetadata.self, from: result.standardOutput)
        } catch {
            throw YouTubeConverterError.toolFailed("No se pudieron leer los datos del vídeo.")
        }
        guard metadata.id == video.videoID else {
            throw YouTubeConverterError.unsupportedVideo
        }
        guard (metadata.duration ?? .infinity) <= 600 else {
            throw YouTubeConverterError.videoTooLong
        }
        return metadata
    }

    func convert(_ request: YouTubeConversionRequest) async throws -> YouTubeConversionResult {
        try await convert(request, onProgress: { _ in })
    }

    func convert(
        _ request: YouTubeConversionRequest,
        onProgress: @escaping @Sendable (YouTubeConversionProgress) -> Void
    ) async throws -> YouTubeConversionResult {
        onProgress(.init(phase: .downloading, fractionCompleted: 0))
        do {
            try Task.checkCancellation()
        } catch {
            throw YouTubeConverterError.cancelled
        }
        let metadata = try await inspect(request)
        do {
            try Task.checkCancellation()
        } catch {
            throw YouTubeConverterError.cancelled
        }
        let video = try YouTubeURL(url: request.url)
        let ytDlp = try toolLocator.url(for: .ytDlp)
        let ffmpeg = try toolLocator.url(for: .ffmpeg)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiyahambaYouTubeConversions", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let template = directory.appendingPathComponent("audio.%(ext)s").path
            let result = try await processExecutor.run(
                executable: ytDlp,
                arguments: [
                    "--no-playlist", "--extract-audio", "--audio-format", request.format.rawValue,
                    "--postprocessor-args", "ffmpeg:-b:a \(request.quality.rawValue)k", "--ffmpeg-location", ffmpeg.path,
                    "--output", template, "--print", "after_move:filepath", video.canonicalURL.absoluteString
                ],
                onOutput: { output in
                    guard let percentage = Self.downloadPercentage(in: output) else { return }
                    onProgress(.init(phase: .downloading, fractionCompleted: min(0.8, percentage * 0.8)))
                }
            )
            onProgress(.init(phase: .converting, fractionCompleted: 0.9))
            guard result.status == 0,
                  let path = String(data: result.standardOutput, encoding: .utf8)?
                    .split(whereSeparator: \.isNewline).last.map(String.init)
            else {
                throw YouTubeConverterError.toolFailed(String(data: result.standardError, encoding: .utf8) ?? "")
            }
            let fileURL = URL(fileURLWithPath: path)
            let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            guard (attributes.fileSize ?? 0) <= 50 * 1024 * 1024 else {
                throw YouTubeConverterError.outputTooLarge
            }
            onProgress(.init(phase: .converting, fractionCompleted: 1))
            return YouTubeConversionResult(fileURL: fileURL, metadata: metadata, sourceURL: video.canonicalURL)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: directory)
            throw YouTubeConverterError.cancelled
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func downloadPercentage(in output: String) -> Double? {
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)%"#
        guard let range = output.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(output[range].dropLast())?.isFinite == true
            ? Double(output[range].dropLast())! / 100
            : nil
    }
}

struct YouTubeURL: Equatable, Sendable {
    let videoID: String
    let canonicalURL: URL

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            throw YouTubeConverterError.invalidURL
        }
        guard components.queryItems?.contains(where: { $0.name == "list" }) != true else {
            throw YouTubeConverterError.playlistNotSupported
        }

        let id: String?
        switch host {
        case "youtu.be", "www.youtu.be":
            id = components.path.split(separator: "/").first.map(String.init)
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            if components.path == "/watch" {
                id = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if components.path.hasPrefix("/shorts/") {
                id = components.path.split(separator: "/").dropFirst().first.map(String.init)
            } else {
                id = nil
            }
        default:
            id = nil
        }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw YouTubeConverterError.invalidURL
        }
        videoID = id
        canonicalURL = URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}
