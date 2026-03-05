import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ImportViewModel.self) private var importViewModel
    var onSongSelected: (SongEntry) -> Void

    @State private var selection = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            ImportView()
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            librarySection
                .frame(maxHeight: .infinity)

            Divider()
            UsageView()
                .layoutPriority(1)
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

            ToolbarItem(placement: .destructiveAction) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        Task { await libraryStore.deleteSongs(ids: selection) }
                        selection = []
                    } label: {
                        Label("Eliminar selección", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        if libraryStore.songs.isEmpty {
            emptyLibraryPlaceholder
        } else {
            Table(libraryStore.songs, selection: $selection) {
                TableColumn("Título") { song in
                    Text(song.title)
                }
                TableColumn("Artista") { song in
                    Text(song.artist ?? "—")
                }
                TableColumn("Tono") { song in
                    Text(song.key ?? "—")
                }
                .width(60)
                TableColumn("Duración") { song in
                    Text(formatDuration(song.duration))
                }
                .width(80)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button(role: .destructive) {
                    Task { await libraryStore.deleteSongs(ids: ids) }
                    selection = selection.subtracting(ids)
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            } primaryAction: { ids in
                guard let id = ids.first,
                      let song = libraryStore.songs.first(where: { $0.id == id }) else { return }
                onSongSelected(song)
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

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
