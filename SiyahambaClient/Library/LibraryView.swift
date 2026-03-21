import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ImportViewModel.self) private var importViewModel
    var onSongSelected: (SongEntry) -> Void

    @State private var selection = Set<UUID>()
    @State private var idsToDelete = Set<UUID>()
    @State private var showDeleteConfirmation = false

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
        .alert(
            "¿Eliminar \(idsToDelete.count == 1 ? "esta canción" : "estas \(idsToDelete.count) canciones")?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                let ids = idsToDelete
                Task { await libraryStore.deleteSongs(ids: ids) }
                selection = selection.subtracting(ids)
                idsToDelete = []
            }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = URL(string: "https://v1.y2mate.nu/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle.fill")
                        Text("YT Convert")
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .help("Abre y2mate para convertir YouTube a MP3")
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
                    if song.isPlaceholder == true {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(song.title)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(song.title)
                    }
                }
                TableColumn("Artista") { song in
                    Text(song.artist ?? "—")
                        .foregroundStyle(song.isPlaceholder == true ? .tertiary : .primary)
                }
                TableColumn("Tono") { song in
                    Text(song.key ?? "—")
                        .foregroundStyle(song.isPlaceholder == true ? .tertiary : .primary)
                }
                .width(60)
                TableColumn("Duración") { song in
                    Text(formatDuration(song.duration))
                        .foregroundStyle(song.isPlaceholder == true ? .tertiary : .primary)
                }
                .width(80)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                let allPlaceholders = ids.allSatisfy { id in
                    libraryStore.songs.first(where: { $0.id == id })?.isPlaceholder == true
                }
                if !allPlaceholders {
                    Button(role: .destructive) {
                        idsToDelete = ids
                        showDeleteConfirmation = true
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
            } primaryAction: { ids in
                guard let id = ids.first,
                      let song = libraryStore.songs.first(where: { $0.id == id }),
                      song.isPlaceholder != true else { return }
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
            Text("Arrastra un archivo de audio para importar")
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
