import DSWaveformImageViews
import SwiftUI

struct WaveformsView: View {
    let songID: UUID

    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.cacheManager) private var cacheManager

    private let stemNames = ["vocals", "drums", "bass", "other"]
    private let stemLabels = ["Voz", "Bateria", "Bajo", "Otro"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<stemNames.count, id: \.self) { i in
                if let cm = cacheManager {
                    StemWaveformRow(
                        stemURL: cm.stemURL(songID: songID, stem: stemNames[i]),
                        stemLabel: stemLabels[i]
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if i < stemNames.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - StemWaveformRow

private struct StemWaveformRow: View {
    let stemURL: URL
    let stemLabel: String

    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                WaveformView(audioURL: stemURL) { shape in
                    shape.fill(Color.teal.opacity(0.7))
                }

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: engine.duration > 0
                        ? geo.size.width * CGFloat(engine.currentTime / engine.duration)
                        : 0)
            }
            .overlay(alignment: .topLeading) {
                Text(stemLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
    }
}
