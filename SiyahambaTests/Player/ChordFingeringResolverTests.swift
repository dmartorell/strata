import Testing
@testable import Siyahamba

struct ChordFingeringResolverTests {
    private let fMajor = ChordPosition(
        frets: [1, 3, 3, 2, 1, 1],
        fingers: [1, 3, 4, 2, 1, 1],
        baseFret: 1,
        barres: [1]
    )
    private let gMajor = ChordPosition(
        frets: [3, 2, 0, 0, 0, 3],
        fingers: [2, 1, 0, 0, 0, 3],
        baseFret: 1,
        barres: []
    )

    @Test("Usa la digitación del acorde mostrado después de transponer")
    func resolvesDisplayedChordAfterTransposition() {
        let sourceEntry = ChordEntry(start: 0, chord: "G", fingerings: [gMajor])

        let result = ChordFingeringResolver.resolve(
            displayedChord: "F",
            mappedFingerings: nil,
            sourceEntry: sourceEntry
        )

        #expect(result.first == fMajor)
    }

    @Test("Conserva la digitación recibida si el acorde no está transpuesto")
    func preservesSourceFingeringWithoutTransposition() {
        let sourceEntry = ChordEntry(start: 0, chord: "G", fingerings: [gMajor])

        let result = ChordFingeringResolver.resolve(
            displayedChord: "G",
            mappedFingerings: nil,
            sourceEntry: sourceEntry
        )

        #expect(result == [gMajor])
    }
}
