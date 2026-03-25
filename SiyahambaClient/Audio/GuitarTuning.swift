import Foundation

// MARK: - GuitarString

enum GuitarString: Int, CaseIterable, Identifiable {
    case e2 = 0
    case a2 = 1
    case d3 = 2
    case g3 = 3
    case b3 = 4
    case e4 = 5

    var id: Int { rawValue }

    var frequency: Double {
        switch self {
        case .e2: return 82.41
        case .a2: return 110.0
        case .d3: return 146.83
        case .g3: return 196.0
        case .b3: return 246.94
        case .e4: return 329.63
        }
    }

    var displayName: String {
        switch self {
        case .e2: return "E2"
        case .a2: return "A2"
        case .d3: return "D3"
        case .g3: return "G3"
        case .b3: return "B3"
        case .e4: return "E4"
        }
    }

    static func closestString(to pitch: Double) -> GuitarString {
        guard pitch > 0 else { return .e2 }
        return GuitarString.allCases.min(by: {
            abs(log2($0.frequency / pitch)) < abs(log2($1.frequency / pitch))
        }) ?? .e2
    }

    static func deviationInCents(pitch: Double, target: Double) -> Double {
        guard pitch > 0, target > 0 else { return 0 }
        return 1200 * log2(pitch / target)
    }
}
