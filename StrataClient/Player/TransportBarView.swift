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
            nsView.doubleValue = value
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
    @Binding var showLyrics: Bool
    @Binding var showChords: Bool

    @State private var wasPlayingBeforeDrag = false

    var body: some View {
        VStack(spacing: 8) {
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

            ZStack {
                HStack(spacing: 24) {
                    Button {
                        engine.seek(to: max(0, engine.currentTime - 10))
                    } label: {
                        Image(systemName: "gobackward.10")
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
                        engine.seek(to: min(engine.duration, engine.currentTime + 10))
                    } label: {
                        Image(systemName: "goforward.10")
                    }
                    .buttonStyle(.plain)

                    Button {
                    } label: {
                        Image(systemName: "repeat")
                    }
                    .buttonStyle(.plain)
                    .tint(engine.loopStart != nil && engine.loopEnd != nil ? .accentColor : nil)
                    .foregroundStyle(engine.loopStart != nil && engine.loopEnd != nil ? Color.accentColor : Color.primary)
                }

                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        toggleButton(label: "Letras", isActive: $showLyrics)
                        toggleButton(label: "Acordes", isActive: $showChords)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func toggleButton(label: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive.wrappedValue ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive.wrappedValue ? Color.accentColor : Color.primary)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        let minutes = Int(s) / 60
        let secs = Int(s) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
