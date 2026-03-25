import SwiftUI

struct ContentView: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @State private var selectedSong: SongEntry?
    @State private var cachedUsage: UsageData?

    var body: some View {
        Group {
            if let song = selectedSong {
                PlayerView(song: song, onBack: { selectedSong = nil })
            } else {
                LibraryView(cachedUsage: $cachedUsage, onSongSelected: {
                    importViewModel.dismissStatus()
                    selectedSong = $0
                })
            }
        }
        .sheet(isPresented: Binding(
            get: { !importViewModel.pendingItems.isEmpty },
            set: { if !$0 { importViewModel.cancelPending() } }
        )) {
            MetadataConfirmationSheet()
                .environment(importViewModel)
        }
    }
}
