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
            .background(Color(red: 0.10, green: 0.16, blue: 0.27))
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

    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    var body: some View {
        let sublines = splitWords(line.words)
        VStack(alignment: .center, spacing: 4) {
            ForEach(sublines.indices, id: \.self) { idx in
                HStack(spacing: 0) {
                    ForEach(sublines[idx]) { word in
                        Text(word.word + " ")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorForWord(word))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func colorForWord(_ word: LyricWord) -> Color {
        if linePassed { return Self.passedColor }
        if !isActive { return Self.upcomingColor }
        if word.end <= currentTime { return .white }
        if currentTime >= word.start { return .white }
        return Self.upcomingColor
    }

private func splitWords(_ words: [LyricWord], maxPerLine: Int = 6) -> [[LyricWord]] {
        guard !words.isEmpty else { return [] }
        var result: [[LyricWord]] = []
        var i = words.startIndex
        while i < words.endIndex {
            let remaining = words.endIndex - i
            if remaining <= maxPerLine {
                result.append(Array(words[i..<words.endIndex]))
                break
            }
            let searchEnd = min(i + maxPerLine + 2, words.endIndex)
            var breakAt = min(i + (remaining + 1) / 2, i + maxPerLine)
            for j in i..<searchEnd {
                if words[j].word.hasSuffix(",") {
                    breakAt = j + 1
                    break
                }
                let lower = words[j].word.lowercased()
                if (lower == "and" || lower == "y") && j > i {
                    breakAt = j
                    break
                }
            }
            result.append(Array(words[i..<breakAt]))
            i = breakAt
        }
        return result
    }
}
