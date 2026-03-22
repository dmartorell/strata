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
            if importViewModel.phase.isActive || isErrorOrReady {
                progressSection
            }
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

            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Arrastra un archivo de audio aquí")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onDrop(of: [UTType.audio], isTargeted: $isDragTargeted) { providers in
            guard !providers.isEmpty else { return false }

            for provider in providers {
                Task {
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
                        await MainActor.run {
                            importViewModel.startFileImport(from: tempCopy, originalURL: originalURL)
                        }
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
            switch importViewModel.phase {
            case .ready:
                Image(systemName: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text(importViewModel.phase.displayLabel)
                    .font(.subheadline.weight(.medium))
            case .error:
                Image(systemName: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text(importViewModel.phase.displayLabel)
                    .font(.subheadline.weight(.medium))
            default:
                Image(systemName: "arrow.trianglehead.2.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .rotationEffect(.degrees(spinnerRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            spinnerRotation = 360
                        }
                    }
                Text(importViewModel.phase.displayLabel)
                    .font(.subheadline.weight(.medium))
            }
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
    }

    private var badgeColor: Color {
        switch importViewModel.phase {
        case .ready: .green
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
        case .ready, .error: return true
        default: return false
        }
    }
}
