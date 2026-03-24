import SwiftUI

struct MetadataConfirmationSheet: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var vm = importViewModel

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirmar metadatos")
                        .font(.headline)
                    Text("Edita artista y título antes de procesar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            List {
                ForEach($vm.pendingItems) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.fileURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Artista")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                TextField("Artista", text: $item.artist)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Título")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                TextField("Título", text: $item.title)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button("Cancelar") {
                    importViewModel.cancelPending()
                    dismiss()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Procesar todo") {
                    importViewModel.confirmImport()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(importViewModel.pendingItems.allSatisfy { $0.title.trimmingCharacters(in: .whitespaces).isEmpty })
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 300)
    }
}
