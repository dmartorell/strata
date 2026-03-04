import SwiftUI

struct PlayerView: View {
    let song: SongEntry
    let onBack: () -> Void

    var body: some View {
        VStack {
            Button("← Volver") { onBack() }
            Text("PlayerView: \(song.title)")
        }
    }
}
