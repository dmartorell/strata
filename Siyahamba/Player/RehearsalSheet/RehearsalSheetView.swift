import SwiftUI

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RehearsalSheetView: View {
    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("lyrics.fontSize") private var fontSize: Double = 36
    @AppStorage("rehearsalSheet.showReferencePanel") private var showReferencePanel: Bool = true

    @State private var isFollowingPlayback: Bool = true
    @State private var lastAutoScrollOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var showFontSizePopover: Bool = false
    @State private var showOffsetPopover: Bool = false

    private static let background = Color(red: 0.10, green: 0.16, blue: 0.27)
    private static let chordColor = Color(red: 0.47, green: 0.66, blue: 0.84)
    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)

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
            if seen.insert(transposed).inserted {
                result.append(transposed)
            }
        }
        for override in vm.chordOverrides where !override.chord.isEmpty {
            let name: String
            if vm.showTransposed && vm.engine.pitchSemitones != 0 {
                name = ChordTransposer.transpose(override.chord, semitones: vm.engine.pitchSemitones)
            } else {
                name = override.chord
            }
            if !placeholders.contains(name) && seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }

    private var currentChordName: String {
        vm.displayChord
    }

    private var offsetLabel: String {
        let ms = Int((vm.lyricsOffset * 1000).rounded())
        if ms == 0 { return "0ms" }
        return ms > 0 ? "+\(ms)ms" : "\(ms)ms"
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
                        ForEach(Array(vm.rehearsalLines.enumerated()), id: \.element.id) { index, line in
                            RehearsalLineView(
                                line: line,
                                lineIndex: index,
                                isActive: line.id == vm.currentLine?.id,
                                linePassed: line.end <= vm.engine.currentTime + vm.lyricsOffset,
                                fontSize: fontSize,
                                simplify: { $0 },
                                onChordMoved: { from, to in vm.applyChordOverride(lineIndex: index, fromWordIndex: from, toWordIndex: to) },
                                onChordDeleted: { wordIndex in vm.deleteChordOverride(lineIndex: index, wordIndex: wordIndex) },
                                onChordAdded: { wordIndex, chord in vm.addChordOverride(lineIndex: index, wordIndex: wordIndex, chord: chord) },
                                isEditingChord: Bindable(vm).isEditingChord
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
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(offsetLabel)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 90)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
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
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(12)
                .popover(isPresented: $showFontSizePopover) {
                    LyricsFontSizePopover()
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
                    let isCurrent = chordName == currentChordName && !currentChordName.isEmpty
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
                Text(entry.chord)
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

private struct RehearsalLineView: View {
    let line: RehearsalLine
    let lineIndex: Int
    let isActive: Bool
    let linePassed: Bool
    let fontSize: Double
    let simplify: (String) -> String
    let onChordMoved: (Int, Int) -> Void
    let onChordDeleted: (Int) -> Void
    let onChordAdded: (Int, String) -> Void
    @Binding var isEditingChord: Bool

    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)
    private static let chordColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    private var lyricColor: Color {
        if isActive { return .white }
        if linePassed { return Self.passedColor }
        return Self.upcomingColor
    }

    var body: some View {
        RehearsalWordFlow(
            words: line.words,
            fontSize: fontSize,
            lyricColor: lyricColor,
            chordColor: Self.chordColor,
            simplify: simplify,
            onChordMoved: onChordMoved,
            onChordDeleted: onChordDeleted,
            onChordAdded: onChordAdded,
            isEditingChord: $isEditingChord
        )
    }
}

private struct RehearsalWordFlow: View {
    let words: [RehearsalWord]
    let fontSize: Double
    let lyricColor: Color
    let chordColor: Color
    let simplify: (String) -> String
    let onChordMoved: (Int, Int) -> Void
    let onChordDeleted: (Int) -> Void
    let onChordAdded: (Int, String) -> Void
    @Binding var isEditingChord: Bool

    @State private var dropTargetIndex: Int? = nil
    @State private var draggingIndex: Int? = nil
    @State private var editingIndex: Int? = nil
    @State private var editText: String = ""

    private var tailSlotIndex: Int { words.count }

    var body: some View {
        FlowLayout(spacing: CGSize(width: 4, height: 8)) {
            ForEach(words.indices, id: \.self) { index in
                wordCell(index: index, word: words[index])
            }
            tailDropSlot
        }
        .onChange(of: words.map(\.chord)) { _, _ in
            draggingIndex = nil
        }
        .onChange(of: editingIndex) { _, newValue in
            isEditingChord = newValue != nil
        }
    }

    private func wordCell(index: Int, word: RehearsalWord) -> some View {
        let displayChord = word.chord.map { simplify($0) }
        let isTarget = dropTargetIndex == index
        let isEditing = editingIndex == index
        return VStack(alignment: .leading, spacing: 2) {
            if isEditing {
                Text(editText.isEmpty ? "Am" : editText)
                    .font(.system(size: CGFloat(fontSize) * 0.7, weight: .bold))
                    .foregroundStyle(Color.clear)
                    .frame(minWidth: 40)
                    .overlay(alignment: .leading) {
                        FocusedTextField(
                            text: $editText,
                            fontSize: CGFloat(fontSize) * 0.7,
                            textColor: NSColor(chordColor),
                            onCommit: { commitEdit(at: index) },
                            onEscape: { editingIndex = nil }
                        )
                    }
            } else if let chord = displayChord {
                Text(chord)
                    .font(.system(size: CGFloat(fontSize) * 0.7, weight: .bold))
                    .foregroundStyle(chordColor)
                    .opacity(draggingIndex == index ? 0 : 1)
                    .draggable(String(index)) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .onAppear { draggingIndex = index }
                    }
                    .contextMenu {
                        Button {
                            editText = chord
                            editingIndex = index
                        } label: {
                            Label("Editar acorde", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onChordDeleted(index)
                        } label: {
                            Label("Eliminar acorde", systemImage: "trash")
                        }
                    }
            } else {
                Text(" ")
                    .font(.system(size: CGFloat(fontSize) * 0.7, weight: .bold))
                    .foregroundStyle(Color.clear)
            }
            if !word.word.isEmpty {
                Text(word.word)
                    .font(.system(size: CGFloat(fontSize), weight: .bold))
                    .foregroundStyle(lyricColor)
            }
        }
        .padding(.horizontal, word.word.isEmpty ? 6 : 0)
        .onTapGesture(count: 2) {
            guard word.chord == nil else { return }
            editText = ""
            editingIndex = index
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isTarget ? Color.accentColor.opacity(0.3) : Color.clear)
        )
        .dropDestination(for: String.self) { items, _ in
            defer { draggingIndex = nil }
            guard word.chord == nil else { return false }
            guard let first = items.first, let sourceIndex = Int(first) else { return false }
            guard sourceIndex != index else { return false }
            onChordMoved(sourceIndex, index)
            return true
        } isTargeted: { targeted in
            if word.chord != nil {
                dropTargetIndex = nil
            } else {
                dropTargetIndex = targeted ? index : nil
            }
        }
    }

    private func commitEdit(at index: Int) {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        editingIndex = nil
        guard !trimmed.isEmpty else { return }
        guard !ChordFingerings.lookup(trimmed).isEmpty else { return }
        onChordAdded(index, trimmed)
    }

    private var hasLastTailChord: Bool {
        guard let last = words.last else { return false }
        return last.word.isEmpty && last.chord != nil
    }

    private func isLastTailChord(_ index: Int) -> Bool {
        index == words.count - 1 && hasLastTailChord
    }

    private var tailDropSlot: some View {
        let isTarget = dropTargetIndex == tailSlotIndex
        return VStack(alignment: .leading, spacing: 2) {
            Text(" ")
                .font(.system(size: CGFloat(fontSize) * 0.7, weight: .bold))
                .foregroundStyle(Color.clear)
            Text("  ")
                .font(.system(size: CGFloat(fontSize), weight: .bold))
                .foregroundStyle(Color.clear)
        }
        .frame(minWidth: 30)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isTarget ? Color.accentColor.opacity(0.3) : Color.clear)
        )
        .dropDestination(for: String.self) { items, _ in
            defer { draggingIndex = nil }
            guard let first = items.first, let sourceIndex = Int(first) else { return false }
            guard !isLastTailChord(sourceIndex) else { return false }
            onChordMoved(sourceIndex, tailSlotIndex)
            return true
        } isTargeted: { targeted in
            dropTargetIndex = targeted ? tailSlotIndex : nil
        }
    }
}

private struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var textColor: NSColor
    var onCommit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .boldSystemFont(ofSize: fontSize)
        field.textColor = textColor
        field.stringValue = text
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: FocusedTextField
        init(_ parent: FocusedTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        private func resignFocus(_ control: NSControl) {
            control.window?.makeFirstResponder(nil)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                resignFocus(control)
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                resignFocus(control)
                parent.onEscape()
                return true
            }
            return false
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
