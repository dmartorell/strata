import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ImportView: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @State private var isDragTargeted = false

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
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .frame(height: 100)

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
            guard let provider = providers.first else { return false }
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
                guard let url else { return }
                let tempCopy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: tempCopy)
                Task { @MainActor in
                    importViewModel.startFileImport(from: tempCopy)
                }
            }
            return true
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        HStack(spacing: 10) {
            if importViewModel.phase.isActive {
                ProgressView()
                    .controlSize(.small)
            } else {
                statusIcon
            }

            Text(importViewModel.phase.displayLabel)
                .font(.subheadline)
                .foregroundStyle(isErrorPhase ? .red : .primary)
                .lineLimit(2)

            Spacer()

            if importViewModel.phase.isActive {
                Button("Cancelar") {
                    importViewModel.cancel()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusIcon: some View {
        Group {
            switch importViewModel.phase {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            default:
                EmptyView()
            }
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
