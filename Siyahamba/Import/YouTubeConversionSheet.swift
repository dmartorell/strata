import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class YouTubeConversionViewModel {
    enum State: Equatable {
        case form
        case converting
        case error(String)
        case completed
    }

    var urlString = ""
    var format: YouTubeFormat = .mp3
    var quality: YouTubeQuality = .standard
    private(set) var state: State = .form
    private(set) var progress = 0.0
    private(set) var progressPhase: YouTubeConversionPhase = .downloading
    private(set) var completedSong: SongEntry?
    private(set) var diagnosticDetails = ""

    var isConverting: Bool {
        if case .converting = state { return true }
        return false
    }

    var errorMessage: String? {
        guard case .error(let message) = state else { return nil }
        return message
    }

    var progressLabel: String {
        "Convirtiendo"
    }

    @ObservationIgnored private let converter: any YouTubeConverting
    @ObservationIgnored private let importViewModel: ImportViewModel
    @ObservationIgnored private var conversionTask: Task<Void, Never>?

    init(
        converter: any YouTubeConverting = YouTubeConverter(),
        importViewModel: ImportViewModel
    ) {
        self.converter = converter
        self.importViewModel = importViewModel
    }

    func convert() {
        guard !isConverting else { return }
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            state = .error(YouTubeConverterError.invalidURL.localizedDescription)
            return
        }

        state = .converting
        progress = 0
        progressPhase = .downloading
        diagnosticDetails = ""
        completedSong = nil

        let request = YouTubeConversionRequest(url: url, format: format, quality: quality)
        conversionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await converter.convert(request) { [weak self] update in
                    Task { @MainActor in
                        self?.updateProgress(update)
                    }
                }
                guard !Task.isCancelled else { return }
                completedSong = importViewModel.collectYouTubeConversion(result)
                state = .completed
            } catch is CancellationError {
                resetAfterCancellation()
            } catch let error as YouTubeConverterError where error == .cancelled {
                resetAfterCancellation()
            } catch {
                guard !Task.isCancelled else {
                    resetAfterCancellation()
                    return
                }
                diagnosticDetails = diagnosticDetails(for: error)
                state = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard isConverting else { return }
        conversionTask?.cancel()
        resetAfterCancellation()
    }

    func retry() {
        state = .form
        convert()
    }

    func copyDiagnosticDetails() {
        guard !diagnosticDetails.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticDetails, forType: .string)
    }

    private func updateProgress(_ update: YouTubeConversionProgress) {
        guard isConverting else { return }
        progressPhase = update.phase
        progress = max(progress, min(1, update.fractionCompleted))
    }

    private func resetAfterCancellation() {
        conversionTask = nil
        progress = 0
        progressPhase = .downloading
        state = .form
    }

    private func diagnosticDetails(for error: Error) -> String {
        if let converterError = error as? YouTubeConverterError,
           case .toolFailed(let details) = converterError {
            return details
        }
        return error.localizedDescription
    }
}

struct YouTubeConversionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: YouTubeConversionViewModel
    private let onSongSelected: (SongEntry) -> Void

    init(
        viewModel: YouTubeConversionViewModel,
        onSongSelected: @escaping (SongEntry) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSongSelected = onSongSelected
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: 20) {
            Text("Importar desde YouTube")
                .font(.headline)

            TextField("URL del vídeo de YouTube", text: $vm.urlString)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isConverting)

            HStack {
                Picker("Formato", selection: $vm.format) {
                    ForEach(YouTubeFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .disabled(vm.isConverting)

                Picker("Calidad", selection: $vm.quality) {
                    ForEach(YouTubeQuality.allCases, id: \.self) { quality in
                        Text("\(quality.rawValue) kbps").tag(quality)
                    }
                }
                .disabled(vm.isConverting)
            }

            if vm.isConverting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(vm.progressLabel)
                }
                .accessibilityElement(children: .combine)
            }

            if let errorMessage = vm.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    if !vm.diagnosticDetails.isEmpty {
                        Button("Ver detalles") {
                            vm.copyDiagnosticDetails()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            HStack {
                Button("Cancelar") {
                    if vm.isConverting {
                        vm.cancel()
                    } else {
                        dismiss()
                    }
                }

                Spacer()

                if vm.errorMessage != nil {
                    Button("Reintentar") { vm.retry() }
                        .buttonStyle(.borderedProminent)
                } else if !vm.isConverting {
                    Button("Convertir e importar") { vm.convert() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(viewModel.isConverting)
        .onChange(of: viewModel.state) { _, state in
            guard case .completed = state else { return }
            if let song = viewModel.completedSong {
                onSongSelected(song)
            }
            dismiss()
        }
    }
}
