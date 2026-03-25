import SwiftUI

struct PlayerView: View {
    let song: SongEntry
    let onBack: () -> Void

    @State private var playerVM: PlayerViewModel?
    @State private var showLyrics: Bool
    @State private var showChords: Bool
    @AppStorage("chordView.showDiagrams") private var showDiagrams: Bool = true

    init(song: SongEntry, onBack: @escaping () -> Void) {
        self.song = song
        self.onBack = onBack
        let mode = song.displayMode ?? .waveforms
        _showLyrics = State(initialValue: mode == .lyrics || mode == .lyricsAndChords)
        _showChords = State(initialValue: mode == .chords || mode == .lyricsAndChords)
    }
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
            } catch {}
            playerVM = vm
            await vm.loadRemoteMetadata()
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
                    await vm.saveDisplayMode(showLyrics: showLyrics, showChords: showChords)
                    await engine.fadeOutAndStop()
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
        } else {
            VStack(spacing: 0) {
                if showLyrics {
                    LyricsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showLyrics && showChords {
                    Divider()
                }
                if showChords {
                    ChordView(enlarged: !showLyrics)
                        .frame(maxHeight: showLyrics ? (showDiagrams ? 300 : 180) : .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

