import SwiftUI

struct ContentView: View {
    @State private var selectedSong: SongEntry?

    var body: some View {
        if let song = selectedSong {
            PlayerView(song: song, onBack: { selectedSong = nil })
        } else {
            LibraryView(onSongSelected: { selectedSong = $0 })
        }
    }
}
