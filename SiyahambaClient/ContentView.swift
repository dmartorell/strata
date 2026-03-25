import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @State private var selectedSong: SongEntry?
    @State private var cachedUsage: UsageData?
    @State private var isDragTargeted = false

    var body: some View {
        ZStack {
            if let song = selectedSong {
                PlayerView(song: song, onBack: { selectedSong = nil })
            } else {
                LibraryView(cachedUsage: $cachedUsage, onSongSelected: {
                    importViewModel.dismissStatus()
                    selectedSong = $0
                })
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
        .sheet(isPresented: Binding(
            get: { !importViewModel.pendingItems.isEmpty },
            set: { if !$0 { importViewModel.cancelPending() } }
        )) {
            MetadataConfirmationSheet()
                .environment(importViewModel)
        }
    }
}
