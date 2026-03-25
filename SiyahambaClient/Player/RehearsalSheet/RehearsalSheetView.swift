import SwiftUI

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RehearsalSheetView: View {
    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("rehearsalSheet.fontSize") private var fontSize: Double = 22
    @AppStorage("rehearsalSheet.showReferencePanel") private var showReferencePanel: Bool = true
    @AppStorage("chordView.difficultyLevel") private var difficultyLevelRaw: String = DifficultyLevel.avanzado.rawValue

    @State private var isFollowingPlayback: Bool = true
    @State private var lastAutoScrollOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var showFontSizePopover: Bool = false
    @State private var showOffsetPopover: Bool = false

    private static let background = Color(red: 0.10, green: 0.16, blue: 0.27)
    private static let chordColor = Color(red: 0.47, green: 0.66, blue: 0.84)
    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    private func simplified(_ chord: String) -> String {
        let level = DifficultyLevel(rawValue: difficultyLevelRaw) ?? .avanzado
        return ChordSimplifier.simplify(chord, level: level)
    }

    private var uniqueChords: [String] {
        let placeholders: Set<String> = ["N", "-", ""]
        var seen = Set<String>()
        var result: [String] = []
        for entry in vm.chords {
            guard !placeholders.contains(entry.chord) else { continue }
            let transposed: String
            if vm.showTransposed && vm.engine.pitchSemitones != 0 {
                transposed = ChordTransposer.transpose(entry.chord, semitones: vm.engine.pitchSemitones)
            } else {
                transposed = entry.chord
            }
            let name = simplified(transposed)
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }

    private var currentSimplifiedChord: String {
        simplified(vm.displayChord)
    }

    var body: some View {
        if vm.rehearsalLines.isEmpty && vm.chords.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                scrollContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showReferencePanel {
                    Divider()
                    referencePanel
                }
            }
            .background(Self.background)
        }
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if vm.rehearsalLines.isEmpty {
                        chordsOnlyView
                    } else {
                        ForEach(vm.rehearsalLines) { line in
                            RehearsalLineView(
                                line: line,
                                isActive: line.id == vm.currentLine?.id,
                                linePassed: line.end <= vm.engine.currentTime + vm.lyricsOffset,
                                fontSize: fontSize,
                                simplify: simplified
                            )
                            .id(line.id)
                            .onTapGesture {
                                vm.engine.seek(to: line.start)
                            }
                        }
                    }
                }
                .padding(.vertical, 100)
                .padding(.horizontal, 24)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("rehearsalScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "rehearsalScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { newOffset in
                let delta = abs(newOffset - lastAutoScrollOffset)
                if isFollowingPlayback && delta > 2 {
                    isFollowingPlayback = false
                }
                scrollOffset = newOffset
            }
            .onChange(of: vm.currentLine?.id) { _, newID in
                guard isFollowingPlayback, let id = newID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    lastAutoScrollOffset = scrollOffset
                }
            }
            .overlay(alignment: .bottom) {
                if !isFollowingPlayback {
                    Button {
                        isFollowingPlayback = true
                        lastAutoScrollOffset = scrollOffset
                        if let id = vm.currentLine?.id {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    } label: {
                        Label("Seguir reproducción", systemImage: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isFollowingPlayback)
            .overlay(alignment: .topTrailing) {
                Button {
                    showOffsetPopover.toggle()
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 16))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .popover(isPresented: $showOffsetPopover) {
                    LyricsOffsetPopover()
                        .environment(vm)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showFontSizePopover.toggle()
                } label: {
                    Text("Aa")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(12)
                .popover(isPresented: $showFontSizePopover) {
                    RehearsalFontSizePopover(fontSize: $fontSize)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Button {
                    withAnimation { showReferencePanel.toggle() }
                } label: {
                    Image(systemName: showReferencePanel ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset.filled")
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }

    private var referencePanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(uniqueChords, id: \.self) { chordName in
                    let isCurrent = chordName == currentSimplifiedChord && !currentSimplifiedChord.isEmpty
                    VStack(spacing: 4) {
                        Text(chordName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Self.chordColor)
                        ChordDiagramView(
                            fingerings: ChordFingerings.lookup(chordName),
                            chord: chordName,
                            interactive: true
                        )
                        .frame(width: 80, height: 80)
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isCurrent ? Color.white.opacity(0.1) : Color.clear)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 120)
        .background(Self.background)
    }

    private var chordsOnlyView: some View {
        ForEach(vm.chords.filter { !["N", "-", ""].contains($0.chord) }) { entry in
            HStack(spacing: 8) {
                Text(String(format: "%.1fs", entry.start))
                    .font(.system(size: CGFloat(fontSize) * 0.6, design: .monospaced))
                    .foregroundStyle(Self.passedColor)
                Text(simplified(entry.chord))
                    .font(.system(size: CGFloat(fontSize), weight: .bold))
                    .foregroundStyle(Self.chordColor)
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Sin datos de ensayo")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Self.chordColor.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.background)
    }
}

private struct RehearsalFontSizePopover: View {
    @Binding var fontSize: Double

    private let minSize: Double = 14
    private let maxSize: Double = 40
    private let step: Double = 2

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
                fontSize = 22
            }
            .buttonStyle(.bordered)
            .disabled(fontSize == 22)
        }
        .padding(20)
        .frame(minWidth: 200)
    }
}

private struct RehearsalLineView: View {
    let line: RehearsalLine
    let isActive: Bool
    let linePassed: Bool
    let fontSize: Double
    let simplify: (String) -> String

    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)
    private static let chordColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    private var lyricColor: Color {
        if isActive { return .white }
        if linePassed { return Self.passedColor }
        return Self.upcomingColor
    }

    var body: some View {
        RehearsalWordFlow(words: line.words, fontSize: fontSize, lyricColor: lyricColor, chordColor: Self.chordColor, simplify: simplify)
    }
}

private struct RehearsalWordFlow: View {
    let words: [RehearsalWord]
    let fontSize: Double
    let lyricColor: Color
    let chordColor: Color
    let simplify: (String) -> String

    var body: some View {
        FlowLayout(spacing: CGSize(width: 4, height: 8)) {
            ForEach(words.indices, id: \.self) { index in
                let word = words[index]
                let displayChord = word.chord.map { simplify($0) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayChord ?? " ")
                        .font(.system(size: CGFloat(fontSize) * 0.7, weight: .bold))
                        .foregroundStyle(displayChord != nil ? chordColor : Color.clear)
                    Text(word.word)
                        .font(.system(size: CGFloat(fontSize), weight: .bold))
                        .foregroundStyle(lyricColor)
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGSize

    init(spacing: CGSize = CGSize(width: 4, height: 8)) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var firstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if firstInRow {
                rowWidth = size.width
                rowHeight = size.height
                firstInRow = false
            } else if rowWidth + spacing.width + size.width <= containerWidth {
                rowWidth += spacing.width + size.width
                rowHeight = max(rowHeight, size.height)
            } else {
                height += rowHeight + spacing.height
                rowWidth = size.width
                rowHeight = size.height
            }
        }
        height += rowHeight
        return CGSize(width: containerWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        var firstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if firstInRow {
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                rowHeight = size.height
                x += size.width
                firstInRow = false
            } else if x + spacing.width + size.width <= bounds.maxX {
                x += spacing.width
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width
                rowHeight = max(rowHeight, size.height)
            } else {
                y += rowHeight + spacing.height
                x = bounds.minX
                rowHeight = size.height
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width
            }
        }
    }
}
