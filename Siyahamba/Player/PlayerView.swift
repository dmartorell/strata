import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct PlayerView: View {
    let song: SongEntry
    let onBack: () -> Void

    @State private var playerVM: PlayerViewModel?
    @State private var showLyrics: Bool
    @State private var showChords: Bool
    @State private var showRehearsalSheet: Bool
    @State private var isDragTargeted = false
    @AppStorage("chordView.showDiagrams") private var showDiagrams: Bool = true

    init(song: SongEntry, onBack: @escaping () -> Void) {
        self.song = song
        self.onBack = onBack
        let mode = song.displayMode ?? .lyrics
        _showLyrics = State(initialValue: mode == .lyrics || mode == .lyricsAndChords)
        _showChords = State(initialValue: mode == .chords || mode == .lyricsAndChords)
        _showRehearsalSheet = State(initialValue: mode == .rehearsalSheet)
    }
    @FocusState private var isContentFocused: Bool

    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.cacheManager) private var cacheManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ImportViewModel.self) private var importViewModel

    var body: some View {
        ZStack {
            Group {
                if let vm = playerVM {
                    mainContent(vm: vm)
                        .environment(vm)
                } else {
                    ProgressView("Cargando...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            GlobalDropOverlay(isTargeted: isDragTargeted)
        }
        .onDrop(of: [UTType.audio], isTargeted: $isDragTargeted) { providers in
            guard !providers.isEmpty else { return false }
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task {
                var files: [(fileURL: URL, originalURL: URL?)] = []
                for provider in providers {
                    let originalURL: URL? = await withCheckedContinuation { cont in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                            if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                cont.resume(returning: url)
                            } else {
                                cont.resume(returning: nil)
                            }
                        }
                    }
                    let tempURL: URL? = await withCheckedContinuation { cont in
                        provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, error in
                            guard let url else { cont.resume(returning: nil); return }
                            let uniqueDir = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                            try? FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
                            let tempCopy = uniqueDir.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.copyItem(at: url, to: tempCopy)
                            cont.resume(returning: tempCopy)
                        }
                    }
                    if let tempCopy = tempURL {
                        files.append((fileURL: tempCopy, originalURL: originalURL))
                    }
                }
                if !files.isEmpty {
                    await MainActor.run {
                        importViewModel.collectPendingFiles(files)
                    }
                }
            }
            return true
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
            TransportBarView(showLyrics: $showLyrics, showChords: $showChords, showRehearsalSheet: $showRehearsalSheet)
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
        .onKeyPress(characters: CharacterSet(charactersIn: "l")) { _ in
            guard playerVM != nil && !playerVM!.lyrics.isEmpty else { return .ignored }
            showLyrics = true
            showChords = false
            showRehearsalSheet = false
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "a")) { press in
            if press.modifiers.contains(.command) {
                showChords = true
                showLyrics = false
            } else {
                showLyrics = playerVM != nil && !playerVM!.lyrics.isEmpty
                showChords = true
            }
            showRehearsalSheet = false
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "r")) { _ in
            guard playerVM != nil && !playerVM!.chords.isEmpty else { return .ignored }
            showRehearsalSheet = true
            showLyrics = false
            showChords = false
            return .handled
        }
    }

    @ViewBuilder
    private func topBar(vm: PlayerViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await vm.savePitchOffset()
                    await vm.saveDisplayMode(showLyrics: showLyrics, showChords: showChords, showRehearsalSheet: showRehearsalSheet)
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
        if showRehearsalSheet {
            RehearsalSheetView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

