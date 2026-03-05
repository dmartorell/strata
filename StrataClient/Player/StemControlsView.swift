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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if stem.index < stems.count - 1 {
                    Divider()
                }
            }
        }
    }
}

// MARK: - StemRowView

private struct StemRowView: View {
    let label: String
    let stemIndex: Int

    @Environment(PlaybackEngine.self) private var engine
    @State private var volume: Float = 1.0

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .onAppear {
            volume = engine.getVolume(for: stemIndex)
        }
    }

    private var isSoloed: Bool {
        engine.soloedStem == stemIndex
    }
}
