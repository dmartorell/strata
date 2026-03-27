import DSWaveformImageViews
import SwiftUI

struct WaveformsView: View {
    let songID: UUID

    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.cacheManager) private var cacheManager

    @State private var isDraggingLoop = false
    @State private var loopDragStartX: CGFloat = 0
    @State private var loopDragCurrentX: CGFloat = 0

    @State private var draggingEdge: LoopEdge? = nil

    private let stemNames = ["vocals", "drums", "bass", "other"]

    private enum LoopEdge { case start, end }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    ForEach(0..<stemNames.count, id: \.self) { i in
                        if let cm = cacheManager {
                            let muted = engine.effectivelyMuted(i)
                            StemWaveformRow(
                                stemURL: cm.stemURL(songID: songID, stem: stemNames[i]),
                                isMuted: muted
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(muted ? 0.45 : 0.35))
                            .clipped()
                            if i < stemNames.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.leading, 1)
                            }
                        }
                    }
                }

                loopOverlay(geo: geo)

                if isDraggingLoop {
                    dragPreviewOverlay(geo: geo)
                }

                PlayheadView(width: geo.size.width)
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "waveform")
            .gesture(mainDragGesture(geo: geo))
        }
    }

    @ViewBuilder
    private func loopOverlay(geo: GeometryProxy) -> some View {
        if let start = engine.loopStart, let end = engine.loopEnd,
           engine.duration > 0 {
            let x = CGFloat(start / engine.duration) * geo.size.width
            let w = CGFloat((end - start) / engine.duration) * geo.size.width

            Rectangle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: w, height: geo.size.height)
                .offset(x: x)

            loopEdgeHandle(geo: geo, edge: .start, positionX: x)
            loopEdgeHandle(geo: geo, edge: .end, positionX: x + w)
        }
    }

    @ViewBuilder
    private func loopEdgeHandle(geo: GeometryProxy, edge: LoopEdge, positionX: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 20, height: geo.size.height)
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 4, height: geo.size.height)
        }
        .offset(x: positionX - 10)
        .gesture(edgeDragGesture(geo: geo, edge: edge))
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private func dragPreviewOverlay(geo: GeometryProxy) -> some View {
        let minX = min(loopDragStartX, loopDragCurrentX)
        let maxX = max(loopDragStartX, loopDragCurrentX)
        let w = maxX - minX

        Rectangle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: w, height: geo.size.height)
            .offset(x: minX)
    }

    private func mainDragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let optionPressed = NSEvent.modifierFlags.contains(.option)

                if optionPressed && !isDraggingLoop {
                    isDraggingLoop = true
                    loopDragStartX = max(0, min(value.startLocation.x, geo.size.width))
                }

                if isDraggingLoop {
                    loopDragCurrentX = max(0, min(value.location.x, geo.size.width))
                }
            }
            .onEnded { value in
                if isDraggingLoop {
                    let minX = min(loopDragStartX, loopDragCurrentX)
                    let maxX = max(loopDragStartX, loopDragCurrentX)
                    let width = geo.size.width

                    guard width > 0, engine.duration > 0 else {
                        isDraggingLoop = false
                        return
                    }

                    let startFraction = Double(minX / width)
                    let endFraction = Double(maxX / width)
                    let startTime = startFraction * engine.duration
                    let endTime = endFraction * engine.duration

                    if endTime - startTime >= 0.1 {
                        engine.setLoop(start: startTime, end: endTime)
                    }

                    isDraggingLoop = false
                } else {
                    guard draggingEdge == nil, engine.duration > 0 else { return }
                    let fraction = value.location.x / geo.size.width
                    let clamped = max(0, min(1, fraction))
                    engine.seek(to: engine.duration * Double(clamped))
                }
            }
    }

    private func edgeDragGesture(geo: GeometryProxy, edge: LoopEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("waveform"))
            .onChanged { value in
                draggingEdge = edge
                guard geo.size.width > 0, engine.duration > 0 else { return }
                let fraction = Double(max(0, min(value.location.x, geo.size.width)) / geo.size.width)
                let time = fraction * engine.duration

                switch edge {
                case .start:
                    let maxTime = (engine.loopEnd ?? engine.duration) - 0.1
                    engine.setLoopStart(max(0, min(time, maxTime)))
                case .end:
                    let minTime = (engine.loopStart ?? 0) + 0.1
                    engine.setLoopEnd(max(minTime, min(time, engine.duration)))
                }
            }
            .onEnded { _ in
                draggingEdge = nil
            }
    }
}

// MARK: - PlayheadView

private struct PlayheadView: View {
    let width: CGFloat
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 2)
            .offset(x: engine.duration > 0
                ? width * CGFloat(engine.currentTime / engine.duration)
                : 0)
            .animation(.easeOut(duration: 0.15), value: engine.currentTime)
    }
}

// MARK: - StemWaveformRow

private struct StemWaveformRow: View {
    let stemURL: URL
    var isMuted: Bool = false

    var body: some View {
        GeometryReader { geo in
            WaveformView(audioURL: stemURL) { shape in
                shape.fill(Color.cyan.opacity(isMuted ? 0.2 : 0.9))
            }
            .padding(.vertical, geo.size.height * 0.2)
        }
        .animation(.easeOut(duration: 0.2), value: isMuted)
    }
}
