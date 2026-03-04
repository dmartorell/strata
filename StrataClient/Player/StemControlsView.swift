import SwiftUI

struct StemControlsView: View {
    @Environment(PlaybackEngine.self) private var engine

    private let stems: [(label: String, index: Int)] = [
        ("Voz", 0),
        ("Bateria", 1),
        ("Bajo", 2),
        ("Otro", 3)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(stems, id: \.index) { stem in
                StemRowView(label: stem.label, stemIndex: stem.index)
                if stem.index < stems.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - StemRowView

private struct StemRowView: View {
    let label: String
    let stemIndex: Int

    @Environment(PlaybackEngine.self) private var engine
    @State private var volume: Float = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button("M") {
                    engine.setMute(!engine.isMuted(stemIndex), for: stemIndex)
                }
                .buttonStyle(.bordered)
                .tint(engine.isMuted(stemIndex) ? .orange : nil)
                .font(.caption2)
                .controlSize(.mini)

                Button("S") {
                    let currentSolo = isSoloed
                    engine.setSolo(currentSolo ? nil : stemIndex)
                }
                .buttonStyle(.bordered)
                .tint(isSoloed ? .yellow : nil)
                .font(.caption2)
                .controlSize(.mini)
            }

            Slider(
                value: Binding(
                    get: { engine.getVolume(for: stemIndex) },
                    set: { engine.setVolume($0, for: stemIndex) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear {
            volume = engine.getVolume(for: stemIndex)
        }
    }

    private var isSoloed: Bool {
        // PlaybackEngine no expone soloedStem publicamente; comparamos inferido
        // Si todos excepto este estan silenciados efectivamente por solo, asumimos que este esta en solo.
        // Como PlaybackEngine no expone soloedStem, usamos una heuristica:
        // verificamos si este stem tiene volumen efectivo y los demas no
        let others = (0..<4).filter { $0 != stemIndex }
        let thisHasVolume = engine.getVolume(for: stemIndex) > 0 && !engine.isMuted(stemIndex)
        let othersAllSilent = others.allSatisfy { engine.isMuted($0) || engine.getVolume(for: $0) == 0 }
        return thisHasVolume && othersAllSilent && others.contains { !engine.isMuted($0) }
    }
}
