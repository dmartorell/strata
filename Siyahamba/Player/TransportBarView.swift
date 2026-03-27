import AppKit
import SwiftUI

// MARK: - SeekSlider (NSViewRepresentable)

private class SeekNSSlider: NSSlider {
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onDragStart?()
        super.mouseDown(with: event) // bloqueante: devuelve al soltar
        onDragEnd?()
    }
}

private struct SeekSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onDragStart: () -> Void
    var onDragEnd: () -> Void

    func makeNSView(context: Context) -> SeekNSSlider {
        let slider = SeekNSSlider()
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.onDragStart = onDragStart
        slider.onDragEnd = onDragEnd
        return slider
    }

    func updateNSView(_ nsView: SeekNSSlider, context: Context) {
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        if !context.coordinator.isDragging {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                nsView.animator().doubleValue = value
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: SeekSlider
        var isDragging = false

        init(_ parent: SeekSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: SeekNSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

// MARK: - TransportBarView

struct TransportBarView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(PlayerViewModel.self) private var vm
    @Binding var showLyrics: Bool
    @Binding var showChords: Bool
    @Binding var showRehearsalSheet: Bool

    @State private var wasPlayingBeforeDrag = false
    @State private var showPitchPopover = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(formatTime(engine.currentTime))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)

                    SeekSlider(
                        value: Binding(
                            get: { engine.currentTime },
                            set: { engine.seek(to: $0) }
                        ),
                        range: 0...max(engine.duration, 1),
                        onDragStart: {
                            wasPlayingBeforeDrag = engine.isPlaying
                            if engine.isPlaying { engine.pause() }
                        },
                        onDragEnd: {
                            if wasPlayingBeforeDrag { engine.play() }
                        }
                    )

                    Text(formatTime(engine.duration))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .leading)
                }
                .frame(width: 450)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ZStack {
                HStack(spacing: 24) {
                    transportButton("gobackward.5") {
                        engine.seek(to: max(0, engine.currentTime - 5))
                    }
                    transportButton(engine.isPlaying ? "pause.fill" : "play.fill", large: true) {
                        if engine.isPlaying { engine.pause() } else { engine.play() }
                    }
                    transportButton("goforward.5") {
                        engine.seek(to: min(engine.duration, engine.currentTime + 5))
                    }
                    transportButton("backward.end.fill") {
                        engine.seek(to: 0)
                    }
                }

                HStack {
                    Spacer()
                    HStack(spacing: 16) {
                        panelToggle("Letras", icon: "text.quote", isActive: showLyrics, enabled: hasLyrics && (showChords || !showLyrics)) {
                            showRehearsalSheet = false
                            showLyrics.toggle()
                        }
                        panelToggle("Acordes", icon: "music.quarternote.3", isActive: showChords, enabled: showLyrics || !showChords) {
                            showRehearsalSheet = false
                            showChords.toggle()
                        }
                        panelToggle("Estudio", icon: "music.note.list", isActive: showRehearsalSheet, enabled: hasChords) {
                            showRehearsalSheet.toggle()
                            if showRehearsalSheet {
                                showLyrics = false
                                showChords = false
                            } else {
                                showLyrics = true
                            }
                        }

                        Button {
                            showPitchPopover.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                Text(pitchLabel)
                                    .monospacedDigit()
                            }
                            .frame(width: 50)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.15))
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showPitchPopover) {
                            PitchPopover()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(SidebarVisualEffect())
    }

    private var hasLyrics: Bool {
        !vm.lyrics.isEmpty
    }

    private var hasChords: Bool {
        !vm.chords.isEmpty
    }

    private func panelToggle(_ label: String, icon: String, isActive: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor : Color.gray.opacity(0.15))
                )
                .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func transportButton(_ icon: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(large ? .title : .body)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(TransportButtonStyle())
    }

    private var pitchLabel: String {
        let semitones = engine.pitchSemitones
        if let key = vm.song.key {
            return ChordTransposer.transpose(key, semitones: semitones)
        }
        if semitones == 0 { return "0" }
        return semitones > 0 ? "+\(semitones)" : "\(semitones)"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        let minutes = Int(s) / 60
        let secs = Int(s) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct TransportButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
