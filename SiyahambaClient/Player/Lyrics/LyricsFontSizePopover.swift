import SwiftUI

struct LyricsFontSizePopover: View {
    @AppStorage("lyrics.fontSize") private var fontSize: Double = 36

    private let minSize: Double = 36
    private let maxSize: Double = 56
    private let step: Double = 4

    var body: some View {
        VStack(spacing: 12) {
            Text("Tamaño letra")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(Int(fontSize))pt")
                .font(.title2)
                .monospacedDigit()

            HStack(spacing: 16) {
                Button("A−") {
                    fontSize = max(minSize, fontSize - step)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(fontSize <= minSize)

                Button("A+") {
                    fontSize = min(maxSize, fontSize + step)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(fontSize >= maxSize)
            }

            Button("Restablecer") {
                fontSize = 36
            }
            .buttonStyle(.bordered)
            .disabled(fontSize == 36)
        }
        .padding(20)
        .frame(minWidth: 200)
    }
}
