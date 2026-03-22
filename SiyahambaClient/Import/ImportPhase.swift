import Foundation

enum ImportPhase: Equatable {
    case idle
    case validating
    case uploading
    case processing(stage: String)
    case ready(cached: Bool)
    case error(String)

    var displayLabel: String {
        switch self {
        case .idle:              return ""
        case .validating:        return "Validando..."
        case .uploading:         return "Subiendo archivo..."
        case .processing(let s): return stageLabel(s)
        case .ready:             return "Finalizado"
        case .error(let msg):    return "Error: \(msg)"
        }
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "queued":           return "En cola..."
        case "separating":       return "Separando stems..."
        case "detecting_chords": return "Detectando acordes..."
        case "packaging":        return "Empaquetando..."
        default:                 return "Procesando..."
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .ready, .error: return false
        default: return true
        }
    }
}
