import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(vm.lyrics) { line in
                        LyricLineView(
                            line: line,
                            isActive: line.id == vm.currentLine?.id,
                            activeWord: line.id == vm.currentLine?.id ? vm.currentWord : nil,
                            currentTime: vm.engine.currentTime,
                            linePassed: line.end <= vm.engine.currentTime
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 200)
            }
            .background(Color.black)
            .onChange(of: vm.currentLine?.id) { _, newID in
                guard let id = newID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

private struct LyricLineView: View {
    let line: LyricLine
    let isActive: Bool
    let activeWord: LyricWord?
    let currentTime: TimeInterval
    let linePassed: Bool

    private var lineOpacity: Double {
        (isActive || linePassed) ? 1.0 : 0.4
    }

    var body: some View {
        let sublines = splitWords(line.words)
        VStack(alignment: .center, spacing: 4) {
            ForEach(sublines.indices, id: \.self) { idx in
                HStack(spacing: 0) {
                    ForEach(sublines[idx]) { word in
                        let isHighlighted = activeWord?.id == word.id
                        let passed = word.end <= currentTime
                        Text(word.word + " ")
                            .font(.system(size: 28, weight: isHighlighted ? .bold : .regular))
                            .foregroundColor(wordColor(isHighlighted: isHighlighted, passed: passed))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(lineOpacity)
    }

    private func wordColor(isHighlighted: Bool, passed: Bool) -> Color {
        if isHighlighted { return .white }
        if passed { return .white }
        return .gray
    }

    private func splitWords(_ words: [LyricWord], maxPerLine: Int = 6) -> [[LyricWord]] {
        guard !words.isEmpty else { return [] }
        var result: [[LyricWord]] = []
        var i = words.startIndex
        while i < words.endIndex {
            let end = min(i + maxPerLine, words.endIndex)
            result.append(Array(words[i..<end]))
            i = end
        }
        return result
    }
}
