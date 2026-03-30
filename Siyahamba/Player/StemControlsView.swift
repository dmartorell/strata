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

    var body: some View {
        VStack(spacing: 0) {
            VocalToggleView()
                .frame(maxWidth: .infinity)
                .frame(height: 96)
            Spacer()
            TunerView()
        }
        .background(SidebarVisualEffect())
    }
}

// MARK: - VocalToggleView

private struct VocalToggleView: View {
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        let vocalsOn = engine.vocalsEnabled

        Button {
            engine.setVocals(enabled: !vocalsOn)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: vocalsOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                Text(vocalsOn ? "Voz activada" : "Voz desactivada")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(vocalsOn ? .primary : .orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(vocalsOn ? Color.white.opacity(0.06) : Color.orange.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .animation(.easeOut(duration: 0.15), value: vocalsOn)
    }
}
