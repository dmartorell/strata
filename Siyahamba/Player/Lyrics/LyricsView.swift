import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("lyrics.fontSize") private var fontSize: Double = 36
    @State private var showOffsetPopover = false
    @State private var showFontSizePopover = false

    var body: some View {
        if vm.isLoadingLyrics {
            loadingState
        } else if vm.lyrics.isEmpty {
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
                                    linePassed: {
                                        guard let current = vm.currentLine else { return false }
                                        return line.end <= current.start
                                    }(),
                                    fontSize: fontSize
                                )
                                .id(line.id)
                                .onTapGesture {
                                    vm.engine.seek(to: line.start)
                                }
                            }
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
            .background(Color(red: 0.10, green: 0.16, blue: 0.27))
        }
    }

    private var offsetLabel: String {
        let ms = Int((vm.lyricsOffset * 1000).rounded())
        if ms == 0 { return "0ms" }
        return ms > 0 ? "+\(ms)ms" : "\(ms)ms"
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(Color(red: 0.47, green: 0.66, blue: 0.84))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.16, blue: 0.27))
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No he encontrado letra\n¡Toca improvisar!")
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
    var fontSize: Double = 36

    private static let passedColor = Color(red: 0.30, green: 0.44, blue: 0.58)
    private static let upcomingColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    private var lineColor: Color {
        if isActive { return .white }
        if linePassed { return Self.passedColor }
        return Self.upcomingColor
    }

    var body: some View {
        Text(line.text)
            .font(.system(size: CGFloat(fontSize), weight: .bold))
            .foregroundColor(lineColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
