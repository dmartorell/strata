import SwiftUI

struct ChordView: View {
    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("chordView.showDiagrams") private var showDiagrams: Bool = true

    private var hasFingerings: Bool {
        vm.chords.first?.fingerings != nil
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
        return []
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if vm.chords.isEmpty {
                Text("Sin acordes")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    currentChordColumn
                    if !vm.displayNextChord.isEmpty {
                        nextChordColumn
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if hasFingerings {
                Button {
                    showDiagrams.toggle()
                } label: {
                    Image(systemName: showDiagrams ? "hand.raised.fingers.spread.fill" : "hand.raised.fingers.spread")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var currentChordColumn: some View {
        VStack(spacing: 8) {
            Text(vm.displayChord.isEmpty ? " " : vm.displayChord)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: vm.displayChord)

            if showDiagrams && hasFingerings && !vm.displayChord.isEmpty {
                let currentFingerings = fingerings(for: vm.displayChord, fallbackEntry: vm.currentChord)
                if !currentFingerings.isEmpty {
                    ChordDiagramView(fingerings: currentFingerings, chord: vm.displayChord)
                        .frame(width: 100, height: 120)
                }
            }
        }
    }

    @ViewBuilder
    private var nextChordColumn: some View {
        VStack(spacing: 8) {
            Text(vm.displayNextChord)
                .font(.system(size: 36, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: vm.displayNextChord)

            if showDiagrams && hasFingerings && !vm.displayNextChord.isEmpty {
                let nextFingerings = fingerings(for: vm.displayNextChord, fallbackEntry: vm.nextChord)
                if !nextFingerings.isEmpty {
                    ChordDiagramView(fingerings: nextFingerings, chord: vm.displayNextChord)
                        .frame(width: 70, height: 84)
                        .opacity(0.5)
                }
            }
        }
        .opacity(0.5)
    }
}
