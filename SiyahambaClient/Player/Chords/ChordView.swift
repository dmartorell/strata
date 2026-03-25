import SwiftUI

struct ChordView: View {
    var enlarged: Bool = false

    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("chordView.showDiagrams") private var showDiagrams: Bool = true
    @AppStorage("chordView.difficultyLevel") private var difficultyLevelRaw: String = DifficultyLevel.avanzado.rawValue

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

    private func simplified(_ chordName: String) -> String {
        let level = DifficultyLevel(rawValue: difficultyLevelRaw) ?? .avanzado
        return ChordSimplifier.simplify(chordName, level: level)
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
                    if !simplified(vm.displayNextChord).isEmpty {
                        nextChordColumn
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                Picker("Nivel", selection: $difficultyLevelRaw) {
                    ForEach(DifficultyLevel.allCases, id: \.rawValue) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if hasFingerings {
                    Button {
                        showDiagrams.toggle()
                    } label: {
                        Image(systemName: showDiagrams ? "square.grid.3x3.fill" : "square.grid.3x3")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var currentChordColumn: some View {
        let displayCurrent = simplified(vm.displayChord)
        VStack(spacing: enlarged ? 8 : 4) {
            Text(displayCurrent.isEmpty ? " " : displayCurrent)
                .font(.system(size: enlarged ? 128 : 64, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: displayCurrent)
                .offset(x: enlarged ? -28 : -14)

            if showDiagrams && hasFingerings && !displayCurrent.isEmpty {
                let currentFingerings = fingerings(for: displayCurrent, fallbackEntry: vm.currentChord)
                if !currentFingerings.isEmpty {
                    ChordDiagramView(fingerings: currentFingerings, chord: displayCurrent)
                        .frame(width: enlarged ? 280 : 140, height: enlarged ? 280 : 140)
                }
            }
        }
    }

    @ViewBuilder
    private var nextChordColumn: some View {
        let displayNext = simplified(vm.displayNextChord)
        VStack(spacing: enlarged ? 8 : 4) {
            Text(displayNext)
                .font(.system(size: enlarged ? 64 : 32, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: displayNext)
                .offset(x: enlarged ? -19 : -10)

            if showDiagrams && hasFingerings && !displayNext.isEmpty {
                let nextFingerings = fingerings(for: displayNext, fallbackEntry: vm.nextChord)
                if !nextFingerings.isEmpty {
                    ChordDiagramView(fingerings: nextFingerings, chord: displayNext, interactive: false)
                        .frame(width: enlarged ? 192 : 96, height: enlarged ? 192 : 96)
                        .opacity(0.5)
                }
            }
        }
        .opacity(0.5)
    }
}
