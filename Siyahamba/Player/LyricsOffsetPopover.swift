import SwiftUI

struct LyricsOffsetPopover: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 12) {
            Text("Sync letras")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(format: "%+.0f ms", vm.lyricsOffset * 1000))
                .font(.title2)
                .monospacedDigit()

            HStack(spacing: 16) {
                Button("−") {
                    vm.lyricsOffset -= 0.1
                    Task { await vm.saveLyricsOffset() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("+") {
                    vm.lyricsOffset += 0.1
                    Task { await vm.saveLyricsOffset() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button("Restablecer") {
                vm.lyricsOffset = 0
                Task { await vm.saveLyricsOffset() }
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(minWidth: 200)
    }
}
