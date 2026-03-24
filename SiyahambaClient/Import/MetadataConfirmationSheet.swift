import SwiftUI

struct MetadataConfirmationSheet: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var vm = importViewModel

        VStack(spacing: 0) {
            header
            Divider()
            itemList(vm: _vm)
            Divider()
            footer
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private func itemList(vm: Bindable<ImportViewModel>) -> some View {
        List {
            ForEach(vm.pendingItems) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        TextField("Artista", text: $item.artist)
                            .textFieldStyle(.roundedBorder)

                        TextField("Título", text: $item.title)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }

    private var footer: some View {
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
}
