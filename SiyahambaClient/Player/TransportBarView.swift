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

    @State private var wasPlayingBeforeDrag = false
    @State private var showPitchPopover = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(formatTime(engine.currentTime))
                        .font(.caption)
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
                        .font(.caption)
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
                    Button {
                        engine.seek(to: max(0, engine.currentTime - 5))
                    } label: {
                        Image(systemName: "gobackward.5")
                    }
                    .buttonStyle(.plain)

                    Button {
                        if engine.isPlaying {
                            engine.pause()
                        } else {
                            engine.play()
                        }
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.seek(to: min(engine.duration, engine.currentTime + 5))
                    } label: {
                        Image(systemName: "goforward.5")
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.seek(to: 0)
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.clearLoop()
                    } label: {
                        Image(systemName: "repeat")
                            .fontWeight(.bold)
                            .foregroundStyle(hasLoop ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .opacity(hasLoop ? 1 : 0.4)
                }

                HStack {
                    Spacer()
                    HStack(spacing: 16) {
                        panelToggle("Letras", icon: "text.quote", isActive: showLyrics) {
                            showLyrics.toggle()
                        }
                        panelToggle("Acordes", icon: "music.quarternote.3", isActive: showChords) {
                            showChords.toggle()
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
                        }
                        .buttonStyle(.bordered)
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

    @ViewBuilder
    private func panelToggle(_ label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        if isActive {
            Button(action: action) {
                Label(label, systemImage: icon)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(label, systemImage: icon)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
        }
    }

    private var hasLoop: Bool {
        engine.loopStart != nil && engine.loopEnd != nil
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
