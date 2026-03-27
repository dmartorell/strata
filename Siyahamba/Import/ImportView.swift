import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ImportView: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @State private var isDragTargeted = false
    @State private var spinnerRotation: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            dropZone
            progressSection
                .opacity(importViewModel.phase == .idle ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: importViewModel.phase == .idle)
        }
        .padding()
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .frame(height: 160)
                .frame(maxWidth: 700)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Arrastra un archivo de audio aquí")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("Selecciona archivo") { openFilePicker() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .onDrop(of: [UTType.audio], isTargeted: $isDragTargeted) { providers in
            guard !providers.isEmpty else { return false }

            NSApplication.shared.activate(ignoringOtherApps: true)

            Task {
                var files: [(fileURL: URL, originalURL: URL?)] = []

                for provider in providers {
                    let originalURL: URL? = await withCheckedContinuation { cont in
                        _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _, _ in
                            cont.resume(returning: url)
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
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                statusBadge
                if importViewModel.queueCount > 0 {
                    Text("\(importViewModel.queueCount) en cola")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if importViewModel.phase.isActive {
                Button(importViewModel.queueCount > 0 ? "Cancelar todo" : "Cancelar") {
                    importViewModel.cancel()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: badgeIcon)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(.degrees(importViewModel.phase.isActive ? spinnerRotation : 0))
                .onAppear {
                    if importViewModel.phase.isActive {
                        spinnerRotation = 0
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            spinnerRotation = 360
                        }
                    }
                }
                .onChange(of: importViewModel.phase.isActive) { _, active in
                    if active {
                        spinnerRotation = 0
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            spinnerRotation = 360
                        }
                    }
                }
            Text(importViewModel.phase.displayLabel)
                .font(.subheadline.weight(.medium))
                .contentTransition(.numericText())
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(badgeColor.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: badgeColor)
    }

    private var badgeIcon: String {
        switch importViewModel.phase {
        case .ready: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .error: "exclamationmark.circle"
        default: "arrow.trianglehead.2.counterclockwise"
        }
    }

    private var badgeColor: Color {
        switch importViewModel.phase {
        case .ready: .green
        case .cancelled: .orange
        case .error: .red
        default: .purple
        }
    }

    private var isErrorPhase: Bool {
        if case .error = importViewModel.phase { return true }
        return false
    }

    private var isErrorOrReady: Bool {
        switch importViewModel.phase {
        case .ready, .cancelled, .error: return true
        default: return false
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let files: [(fileURL: URL, originalURL: URL?)] = panel.urls.map { url in
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let copy = tmpDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: copy)
            return (fileURL: copy, originalURL: url)
        }
        importViewModel.collectPendingFiles(files)
    }
}
