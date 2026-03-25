import SwiftUI

struct ChordView: View {
    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("chordView.showDiagrams") private var showDiagrams: Bool = true

    private var hasFingerings: Bool {
        !vm.chords.isEmpty
    }

    private var fingeringsMap: [String: [ChordPosition]] {
        var map: [String: [ChordPosition]] = [:]
        for entry in vm.chords {
            if let f = entry.fingerings, !f.isEmpty {
                map[entry.chord] = f
            }
        }
        return map
    }

    private func fingerings(for chordName: String, fallbackEntry: ChordEntry?) -> [ChordPosition] {
        if let f = fingeringsMap[chordName], !f.isEmpty { return f }
        if let f = fallbackEntry?.fingerings, !f.isEmpty { return f }
        return ChordFingerings.lookup(chordName)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if vm.chords.isEmpty {
                Text("Sin acordes")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 48) {
                    currentChordColumn
                    if !vm.displayNextChord.isEmpty {
                        nextChordColumn
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if hasFingerings {
                Button {
                    showDiagrams.toggle()
                } label: {
                    Image(systemName: showDiagrams ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var currentChordColumn: some View {
        VStack(spacing: 4) {
            Text(vm.displayChord.isEmpty ? " " : vm.displayChord)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: vm.displayChord)
                .offset(x: -9)

            if showDiagrams && hasFingerings && !vm.displayChord.isEmpty {
                let currentFingerings = fingerings(for: vm.displayChord, fallbackEntry: vm.currentChord)
                if !currentFingerings.isEmpty {
                    ChordDiagramView(fingerings: currentFingerings, chord: vm.displayChord)
                        .frame(width: 140, height: 130)
                }
            }
        }
    }

    @ViewBuilder
    private var nextChordColumn: some View {
        VStack(spacing: 4) {
            Text(vm.displayNextChord)
                .font(.system(size: 32, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: vm.displayNextChord)
                .offset(x: -6)

            if showDiagrams && hasFingerings && !vm.displayNextChord.isEmpty {
                let nextFingerings = fingerings(for: vm.displayNextChord, fallbackEntry: vm.nextChord)
                if !nextFingerings.isEmpty {
                    ChordDiagramView(fingerings: nextFingerings, chord: vm.displayNextChord)
                        .frame(width: 96, height: 90)
                        .opacity(0.5)
                }
            }
        }
        .opacity(0.5)
    }
}
