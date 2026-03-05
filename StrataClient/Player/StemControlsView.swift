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
                    .background(Color.white.opacity(0.03))
                if stem.index < stems.count - 1 {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.trailing, 1)
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
                stemToggleButton("M", isActive: engine.isMuted(stemIndex), activeColor: .orange) {
                    engine.setMute(!engine.isMuted(stemIndex), for: stemIndex)
                }

                stemToggleButton("S", isActive: isSoloed, activeColor: .yellow) {
                    engine.toggleSolo(for: stemIndex)
                }
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
        engine.soloedStems.contains(stemIndex)
    }

    @ViewBuilder
    private func stemToggleButton(_ label: String, isActive: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.bold())
                .frame(width: 22, height: 18)
                .foregroundStyle(isActive ? .black : .secondary)
                .background(isActive ? activeColor : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
