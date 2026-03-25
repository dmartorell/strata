import SwiftUI
import AppKit

// MARK: - Sidebar VisualEffect (Xcode-style behind-window blur)

struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - StemControlsView

struct StemControlsView: View {
    @Environment(PlaybackEngine.self) private var engine

    private let stems: [(label: String, index: Int)] = [
        ("Voz", 0),
        ("Batería", 1),
        ("Bajo", 2),
        ("Otro", 3)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(stems, id: \.index) { stem in
                StemRowView(label: stem.label, stemIndex: stem.index)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                if stem.index < stems.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
            }
            Spacer()
            TunerView()
        }
        .background(SidebarVisualEffect())
    }
}

// MARK: - StemRowView

private struct StemRowView: View {
    let label: String
    let stemIndex: Int

    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        let muted = engine.effectivelyMuted(stemIndex)

        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(muted ? .tertiary : .secondary)
                .frame(width: 52, alignment: .leading)

            stemToggleButton("M", isActive: engine.isMuted(stemIndex), activeColor: .orange) {
                engine.setMute(!engine.isMuted(stemIndex), for: stemIndex)
            }

            stemToggleButton("S", isActive: isSoloed, activeColor: .yellow) {
                engine.toggleSolo(for: stemIndex)
            }

            StemVolumeSlider(
                value: Binding(
                    get: { engine.getVolume(for: stemIndex) },
                    set: { engine.setVolume($0, for: stemIndex) }
                )
            )
            .frame(width: 70, height: 12)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .opacity(muted ? 0.6 : 1.0)
        .animation(.easeOut(duration: 0.15), value: muted)
    }

    private var isSoloed: Bool {
        engine.soloedStems.contains(stemIndex)
    }

    @ViewBuilder
    private func stemToggleButton(_ label: String, isActive: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 22, height: 16)
                .foregroundStyle(isActive ? .black : Color.white.opacity(0.4))
                .background(isActive ? activeColor : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StemVolumeSlider

private struct StemVolumeSlider: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let knobSize: CGFloat = 10
            let trackH: CGFloat = 3
            let fillW = CGFloat(value) * (w - knobSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: trackH)

                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: fillW + knobSize / 2, height: trackH)

                Circle()
                    .fill(Color(white: 0.55))
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: fillW)
            }
            .frame(height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let ratio = Float((drag.location.x - knobSize / 2) / (w - knobSize))
                        value = min(max(ratio, 0), 1)
                    }
            )
        }
    }
}
