import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ImportViewModel.self) private var importViewModel

    var body: some View {
        VStack(spacing: 0) {
            ImportView()
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            librarySection
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let urlString = NSPasteboard.general.string(forType: .string) {
                        importViewModel.startURLImport(urlString: urlString)
                    }
                } label: {
                    Label("Pegar URL de YouTube", systemImage: "link")
                }
                .help("Pega una URL de YouTube del portapapeles (⌘V)")
                .disabled(importViewModel.phase.isActive)
            }
        }
    }

    private var librarySection: some View {
        Group {
            if libraryStore.songs.isEmpty {
                emptyLibraryPlaceholder
            } else {
                List(libraryStore.songs) { song in
                    songRow(song)
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyLibraryPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Biblioteca vacía")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Arrastra un archivo o pega una URL de YouTube para importar")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private func songRow(_ song: SongEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title)
                .font(.body)
            if let artist = song.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
