import SwiftUI

struct PlayerView: View {
    let song: SongEntry
    let onBack: () -> Void

    @State private var playerVM: PlayerViewModel?
    @State private var showLyrics = false
    @State private var showChords = false
    @FocusState private var isContentFocused: Bool

    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.cacheManager) private var cacheManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        Group {
            if let vm = playerVM {
                mainContent(vm: vm)
                    .environment(vm)
            } else {
                ProgressView("Cargando...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let vm = PlayerViewModel(
                song: song,
                engine: engine,
                cacheManager: cacheManager!,
                libraryStore: libraryStore
            )
            do {
                try await vm.load()
            } catch {
                // Continuar incluso si falla la carga de metadatos
            }
            playerVM = vm
        }
    }

    @ViewBuilder
    private func mainContent(vm: PlayerViewModel) -> some View {
        VStack(spacing: 0) {
            topBar(vm: vm)
            Divider()
            HStack(spacing: 0) {
                StemControlsView()
                    .frame(width: 260)
                Divider()
                mainZone(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            TransportBarView(showLyrics: $showLyrics, showChords: $showChords)
        }
        .focusable()
        .focused($isContentFocused)
        .focusEffectDisabled()
        .onAppear { isContentFocused = true }
        .onKeyPress(.space) {
            if engine.isPlaying {
                engine.pause()
            } else {
                engine.play()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            engine.seek(to: max(0, engine.currentTime - 5))
            return .handled
        }
        .onKeyPress(.rightArrow) {
            engine.seek(to: min(engine.duration, engine.currentTime + 5))
            return .handled
        }
    }

    @ViewBuilder
    private func topBar(vm: PlayerViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await vm.savePitchOffset()
                    engine.stop()
                    onBack()
                }
            } label: {
                Label("Biblioteca", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(song.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func mainZone(vm: PlayerViewModel) -> some View {
        if !showLyrics && !showChords {
            WaveformsView(songID: song.id)
        } else if showLyrics && !showChords {
            LyricsView()
        } else if showLyrics && showChords {
            VStack(spacing: 0) {
                LyricsView()
                Divider()
                ChordView()
                    .frame(maxHeight: 220)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ChordView()
        }
    }

}

