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
                            activeWord: line.id == vm.currentLine?.id ? vm.currentWord : nil
                        )
                        .id(line.id)
                    }
                }
                .padding(.vertical, 200)
            }
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(line.words) { word in
                let isHighlighted = activeWord?.id == word.id
                Text(word.word + " ")
                    .font(.title2)
                    .fontWeight(isHighlighted ? .bold : .regular)
                    .foregroundColor(isHighlighted ? .accentColor : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(isActive ? 1.0 : 0.4)
    }
}
