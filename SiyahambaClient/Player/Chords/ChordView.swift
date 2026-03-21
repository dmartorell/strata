import SwiftUI

struct ChordView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 24) {
            if vm.chords.isEmpty {
                Text("Sin acordes")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text(vm.displayChord.isEmpty ? " " : vm.displayChord)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: vm.displayChord)

                if !vm.displayNextChord.isEmpty {
                    Text(vm.displayNextChord)
                        .font(.system(size: 36, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: vm.displayNextChord)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
