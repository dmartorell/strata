import SwiftUI

struct GlobalDropOverlay: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.green, lineWidth: 3)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.05))
            )
            .overlay {
                if isTargeted {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.green)
                        Text("Suelta para importar")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .opacity(isTargeted ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            .allowsHitTesting(false)
    }
}
