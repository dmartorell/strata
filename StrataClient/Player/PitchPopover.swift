import SwiftUI

struct PitchPopover: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 12) {
            Text("Tono")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(currentNoteLabel)
                .font(.largeTitle)
                .bold()
                .monospacedDigit()

            HStack(spacing: 16) {
                Button("−") {
                    engine.setPitch(semitones: engine.pitchSemitones - 1)
                    Task { await vm.savePitchOffset() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("\(engine.pitchSemitones)")
                    .font(.title2)
                    .monospacedDigit()
                    .frame(minWidth: 32)

                Button("+") {
                    engine.setPitch(semitones: engine.pitchSemitones + 1)
                    Task { await vm.savePitchOffset() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button("Restablecer") {
                engine.setPitch(semitones: 0)
                Task { await vm.savePitchOffset() }
            }
            .buttonStyle(.bordered)

            if !vm.chords.isEmpty {
                Divider()
                Toggle("Mostrar transpuesto", isOn: Binding(
                    get: { vm.showTransposed },
                    set: { vm.showTransposed = $0 }
                ))
                .toggleStyle(.switch)
            }
        }
        .padding(20)
        .frame(minWidth: 200)
    }

    private var currentNoteLabel: String {
        let semitones = engine.pitchSemitones
        if let key = vm.song.key {
            return ChordTransposer.transpose(key, semitones: semitones)
        }
        if semitones == 0 { return "0" }
        return semitones > 0 ? "+\(semitones)" : "\(semitones)"
    }
}
