import SwiftUI

struct RehearsalReferencePanel: View {
    let uniqueChords: [String]
    @Binding var showPanel: Bool
    var dismissTask: Binding<Task<Void, Never>?>

    private static let background = Color(red: 0.10, green: 0.16, blue: 0.27)
    private static let chordColor = Color(red: 0.47, green: 0.66, blue: 0.84)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(uniqueChords, id: \.self) { chordName in
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 160)
        .background(Self.background)
        .onHover { hovering in
            guard NSApp.isActive else { return }
            if hovering {
                dismissTask.wrappedValue?.cancel()
                dismissTask.wrappedValue = nil
            } else {
                dismissTask.wrappedValue?.cancel()
                dismissTask.wrappedValue = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPanel = false
                    }
                }
            }
        }
    }
}
