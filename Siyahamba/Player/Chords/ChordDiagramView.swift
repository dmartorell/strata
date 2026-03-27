import SwiftUI

struct ChordDiagramView: View {
    let fingerings: [ChordPosition]
    let chord: String
    var interactive: Bool = true
    @State private var variationIndex = 0
    @State private var isHoveringDiagram = false
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
        canvas
            .id(chord + String(variationIndex))
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: chord)
            .animation(.easeInOut(duration: 0.12), value: variationIndex)
            .opacity(isHoveringDiagram && interactive ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHoveringDiagram)
.onHover { inside in
                guard interactive, sortedFingerings.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.12)) { isHoveringDiagram = inside }
            }
            .onTapGesture {
                guard sortedFingerings.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    variationIndex += 1
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
            let scale = size.width / 140
            let oxAreaHeight: CGFloat = 18 * scale
            let fretLabelWidth: CGFloat = 28 * scale
            let sidePadding: CGFloat = 10 * scale

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
            let stringLineWidth: CGFloat = 1 * scale
            let nutOverhang = stringLineWidth / 2
            for f in 0...fretCount {
                let y = gridY + CGFloat(f) * fretSpacing
                let isNut = f == 0 && position.baseFret == 1
                let lw: CGFloat = isNut ? 4 * scale : 1 * scale
                let x0 = isNut ? gridX - nutOverhang : gridX
                let x1 = isNut ? gridX + gridWidth + nutOverhang : gridX + gridWidth
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x0, y: y))
                        p.addLine(to: CGPoint(x: x1, y: y))
                    },
                    with: shading,
                    lineWidth: lw
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
                    lineWidth: 1 * scale
                )
            }

            // Draw O/X indicators above grid
            let oxFont = Font.system(size: 13 * scale)
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
                    at: CGPoint(x: x, y: gridY - 10 * scale),
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
                let labelX = gridX + gridWidth + dotRadius + 6 * scale
                let labelY = gridY + fretSpacing * 0.5
                let fretFont = Font.system(size: 12 * scale)
                context.draw(
                    Text("\(position.baseFret)fr").font(fretFont).foregroundStyle(drawColor),
                    at: CGPoint(x: labelX, y: labelY),
                    anchor: .leading
                )
            }
        }
    }

}
