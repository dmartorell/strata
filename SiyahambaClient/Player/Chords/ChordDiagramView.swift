import SwiftUI

struct ChordDiagramView: View {
    let fingerings: [ChordPosition]
    let chord: String
    @State private var variationIndex = 0
    @Environment(\.colorScheme) private var colorScheme

    private var sortedFingerings: [ChordPosition] {
        fingerings.sorted { $0.baseFret < $1.baseFret }
    }

    private var position: ChordPosition {
        let count = sortedFingerings.count
        guard count > 0 else { return sortedFingerings[0] }
        return sortedFingerings[((variationIndex % count) + count) % count]
    }

    private var drawColor: Color { colorScheme == .dark ? .white : .black }
    private var textColor: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        VStack(spacing: 2) {
            canvas
                .id(chord + String(variationIndex))
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: chord)
                .animation(.easeInOut(duration: 0.12), value: variationIndex)
                .onTapGesture {
                    if sortedFingerings.count > 1 {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            variationIndex += 1
                        }
                    }
                }

            if sortedFingerings.count > 1 {
                navigationRow
            }
        }
        .onChange(of: chord) {
            variationIndex = 0
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            let fretCount = 4
            let stringCount = 6
            let oxAreaHeight: CGFloat = 18
            let fretLabelWidth: CGFloat = 28
            let sidePadding: CGFloat = 10

            let gridX: CGFloat = sidePadding
            let gridY: CGFloat = oxAreaHeight
            let gridWidth = size.width - fretLabelWidth - sidePadding * 2
            let gridHeight = size.height - oxAreaHeight

            let stringSpacing = gridWidth / CGFloat(stringCount - 1)
            let fretSpacing = gridHeight / CGFloat(fretCount)

            let dotRadius = min(stringSpacing, fretSpacing) * 0.38
            let shading = GraphicsContext.Shading.color(drawColor)
            let fingerFont = Font.system(size: dotRadius * 1.3, weight: .bold)

            // Draw fret lines
            for f in 0...fretCount {
                let y = gridY + CGFloat(f) * fretSpacing
                let lineWidth: CGFloat = (f == 0 && position.baseFret == 1) ? 4 : 1
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: gridX, y: y))
                        p.addLine(to: CGPoint(x: gridX + gridWidth, y: y))
                    },
                    with: shading,
                    lineWidth: lineWidth
                )
            }

            // Draw string lines
            for s in 0..<stringCount {
                let x = gridX + CGFloat(s) * stringSpacing
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: gridY))
                        p.addLine(to: CGPoint(x: x, y: gridY + gridHeight))
                    },
                    with: shading,
                    lineWidth: 1
                )
            }

            // Draw O/X indicators above grid
            let oxFont = Font.system(size: 13)
            for s in 0..<min(stringCount, position.frets.count) {
                let fretValue = position.frets[s]
                let label: String
                if fretValue == 0 {
                    label = "O"
                } else if fretValue == -1 {
                    label = "X"
                } else {
                    continue
                }
                let x = gridX + CGFloat(s) * stringSpacing
                context.draw(
                    Text(label).font(oxFont).foregroundStyle(drawColor),
                    at: CGPoint(x: x, y: gridY - 10),
                    anchor: .center
                )
            }

            // Draw barres
            for barreRelFret in position.barres {
                let barreStrings = position.frets.indices.filter { position.frets[$0] == barreRelFret }
                guard barreStrings.count >= 2 else { continue }
                let minString = barreStrings.min()!
                let maxString = barreStrings.max()!
                let x1 = gridX + CGFloat(minString) * stringSpacing
                let x2 = gridX + CGFloat(maxString) * stringSpacing
                let y = gridY + (CGFloat(barreRelFret) - 0.5) * fretSpacing
                let barreRect = CGRect(
                    x: x1 - dotRadius,
                    y: y - dotRadius,
                    width: x2 - x1 + dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Path(roundedRect: barreRect, cornerRadius: dotRadius),
                    with: shading
                )
                let barreFinger = position.fingers.indices.contains(barreStrings.first!) ? position.fingers[barreStrings.first!] : 0
                if barreFinger > 0 {
                    let barreCenterX = (x1 + x2) / 2
                    let barreCenterY = y
                    context.draw(
                        Text("\(barreFinger)").font(fingerFont).foregroundStyle(textColor),
                        at: CGPoint(x: barreCenterX, y: barreCenterY),
                        anchor: .center
                    )
                }
            }

            // Draw finger dots
            let barreSet = Set(position.barres)
            for s in 0..<min(stringCount, position.frets.count) {
                let fretValue = position.frets[s]
                guard fretValue > 0, !barreSet.contains(fretValue) else { continue }
                let x = gridX + CGFloat(s) * stringSpacing
                let y = gridY + (CGFloat(fretValue) - 0.5) * fretSpacing
                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(Path(ellipseIn: dotRect), with: shading)
                let fingerNum = position.fingers.indices.contains(s) ? position.fingers[s] : 0
                if fingerNum > 0 {
                    context.draw(
                        Text("\(fingerNum)").font(fingerFont).foregroundStyle(textColor),
                        at: CGPoint(x: x, y: y),
                        anchor: .center
                    )
                }
            }

            // Draw fret number when baseFret > 1
            if position.baseFret > 1 {
                let labelX = gridX + gridWidth + dotRadius + 6
                let labelY = gridY + fretSpacing * 0.5
                context.draw(
                    Text("\(position.baseFret)fr").font(.caption).foregroundStyle(drawColor),
                    at: CGPoint(x: labelX, y: labelY),
                    anchor: .leading
                )
            }
        }
    }

    private var navigationRow: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { variationIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { variationIndex += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 38)
        .font(.caption)
    }
}
