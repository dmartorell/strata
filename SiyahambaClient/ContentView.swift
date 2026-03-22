import SwiftUI

struct ContentView: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @State private var selectedSong: SongEntry?

    var body: some View {
        if let song = selectedSong {
            PlayerView(song: song, onBack: { selectedSong = nil })
        } else {
            LibraryView(onSongSelected: {
                importViewModel.dismissStatus()
                selectedSong = $0
            })
        }
    }
}
