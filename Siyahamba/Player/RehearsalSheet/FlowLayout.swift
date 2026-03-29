import SwiftUI

struct FlowLayout: Layout {
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
