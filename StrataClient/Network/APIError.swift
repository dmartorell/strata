import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpError(Int)
    case unauthorized          // 401 — dispara logout en AuthViewModel
    case processingFailed(String)
    case timeout               // 60 intentos agotados en polling
    case decodingError(String)
    case rateLimited
    case youtubeAuthExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Respuesta del servidor no válida"
        case .httpError(let code):
            return "Error HTTP \(code)"
        case .unauthorized:
            return "No autorizado — sesión expirada"
        case .processingFailed(let msg):
            return "Fallo en el procesamiento: \(msg)"
        case .timeout:
            return "Tiempo de espera agotado"
        case .decodingError(let msg):
            return "Error decodificando respuesta: \(msg)"
        case .rateLimited:
            return "Limite mensual de procesamiento alcanzado"
        case .youtubeAuthExpired:
            return "No se pudo descargar de YouTube. Prueba subiendo el archivo directamente."
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse): return true
        case (.httpError(let a), .httpError(let b)): return a == b
        case (.unauthorized, .unauthorized): return true
        case (.processingFailed(let a), .processingFailed(let b)): return a == b
        case (.timeout, .timeout): return true
        case (.decodingError(let a), .decodingError(let b)): return a == b
        case (.rateLimited, .rateLimited): return true
        case (.youtubeAuthExpired, .youtubeAuthExpired): return true
        default: return false
        }
    }
}
