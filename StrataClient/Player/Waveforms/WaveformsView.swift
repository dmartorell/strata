import DSWaveformImageViews
import SwiftUI

struct WaveformsView: View {
    let songID: UUID

    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.cacheManager) private var cacheManager

    private let stemNames = ["vocals", "drums", "bass", "other"]

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
                            .background(muted ? Color.white.opacity(0.01) : Color.white.opacity(0.03))
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

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: engine.duration > 0
                        ? geo.size.width * CGFloat(engine.currentTime / engine.duration)
                        : 0)
                    .animation(.easeOut(duration: 0.15), value: engine.currentTime)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard engine.duration > 0 else { return }
                        let fraction = value.location.x / geo.size.width
                        let clamped = max(0, min(1, fraction))
                        engine.seek(to: engine.duration * Double(clamped))
                    }
            )
        }
    }

}

// MARK: - StemWaveformRow

private struct StemWaveformRow: View {
    let stemURL: URL
    var isMuted: Bool = false

    var body: some View {
        GeometryReader { geo in
            WaveformView(audioURL: stemURL) { shape in
                shape.fill(Color.teal.opacity(isMuted ? 0.2 : 0.7))
            }
            .padding(.vertical, geo.size.height * 0.2)
        }
        .animation(.easeOut(duration: 0.2), value: isMuted)
    }
}
