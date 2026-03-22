import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        if vm.lyrics.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(vm.lyrics) { line in
                            if line.words.isEmpty && line.text.isEmpty {
                                Spacer()
                                    .frame(height: 16)
                                    .id(line.id)
                            } else {
                                LyricLineView(
                                    line: line,
                                    isActive: line.id == vm.currentLine?.id,
                                    linePassed: line.end <= vm.engine.currentTime + vm.lyricsOffset
                                )
                                .id(line.id)
                            }
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

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No tenemos letra, ¡improvisa!")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(red: 0.47, green: 0.66, blue: 0.84).opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.16, blue: 0.27))
    }
}

private struct LyricLineView: View {
    let line: LyricLine
    let isActive: Bool
    let linePassed: Bool

    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    private var lineColor: Color {
        if isActive { return .white }
        if linePassed { return Self.passedColor }
        return Self.upcomingColor
    }

    var body: some View {
        Text(line.text)
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(lineColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
