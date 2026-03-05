import SwiftUI

struct PlayerView: View {
    let song: SongEntry
    let onBack: () -> Void

    @State private var playerVM: PlayerViewModel?
    @State private var showLyrics = false
    @State private var showChords = false
    @State private var showPitchPopover = false
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
                    .frame(width: 140)
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

            Button {
                showPitchPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                    Text(pitchLabel(song: song))
                        .monospacedDigit()
                }
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showPitchPopover) {
                PitchPopover()
                    .environment(vm)
            }

            ABLoopButton()
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

    private func pitchLabel(song: SongEntry) -> String {
        let semitones = engine.pitchSemitones
        if let key = song.key {
            let transposed = ChordTransposer.transpose(key, semitones: semitones)
            return transposed
        }
        if semitones == 0 { return "0" }
        return semitones > 0 ? "+\(semitones)" : "\(semitones)"
    }
}

// MARK: - A/B Loop Button

private struct ABLoopButton: View {
    @Environment(PlaybackEngine.self) private var engine
    @State private var loopPhase: LoopPhase = .idle

    private enum LoopPhase { case idle, startSet, active }

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                Text(loopLabel)
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .tint(loopPhase == .active ? .accentColor : nil)
    }

    private var loopLabel: String {
        switch loopPhase {
        case .idle: return "A/B"
        case .startSet: return "A…"
        case .active: return "Loop"
        }
    }

    private func handleTap() {
        switch loopPhase {
        case .idle:
            engine.setLoopStart(engine.currentTime)
            loopPhase = .startSet
        case .startSet:
            let end = engine.currentTime
            if let start = engine.loopStart, end > start {
                engine.setLoopEnd(end)
                loopPhase = .active
            } else {
                engine.clearLoop()
                loopPhase = .idle
            }
        case .active:
            engine.clearLoop()
            loopPhase = .idle
        }
    }
}
