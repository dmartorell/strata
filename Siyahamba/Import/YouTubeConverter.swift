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
