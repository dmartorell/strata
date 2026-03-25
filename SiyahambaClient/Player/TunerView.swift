import SwiftUI

// MARK: - TunerView

struct TunerView: View {
    @Environment(TunerEngine.self) private var tuner
    @Environment(PlaybackEngine.self) private var engine
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))

            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }

            tunerLabel
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                if isExpanded {
                    tuner.stop()
                    isExpanded = false
                } else {
                    isExpanded = true
                    tuner.start()
                }
            }
        }
        .onDisappear {
            if tuner.isActive {
                tuner.stopWithoutResume()
                isExpanded = false
            }
        }
        .onChange(of: engine.isPlaying) { _, playing in
            if playing && tuner.isActive {
                tuner.stopWithoutResume()
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded = false
                }
            }
        }
    }

    private var tunerLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "tuningfork")
                .font(.system(size: 11))
            Text("Afinar")
                .font(.system(size: 11))
                .animation(nil, value: isExpanded)
        }
        .foregroundStyle(isExpanded ? Color.yellow : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 8) {
            if tuner.permissionDenied {
                Text("Micrófono no disponible")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                pitchDisplay
                deviationBar
                Spacer().frame(height: 3)
                stringSelector
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Pitch Display

    private var pitchDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(tuner.detectedPitch > 0 ? tuner.closestString.displayName : "--")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .frame(minWidth: 36)

            Text(centsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var centsText: String {
        guard tuner.detectedPitch > 0 else { return "—" }
        let cents = Int(tuner.deviationCents.rounded())
        if cents > 0 { return "+\(cents) cents" }
        if cents < 0 { return "\(cents) cents" }
        return "0 cents"
    }

    // MARK: - Deviation Bar

    private var deviationBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let halfW = w / 2
            let maxCents: Double = 50
            let clamped = max(-maxCents, min(maxCents, tuner.detectedPitch > 0 ? tuner.deviationCents : 0))
            let offset = CGFloat(clamped / maxCents) * (halfW - 6)
            let indicatorColor = indicatorColor(for: tuner.deviationCents, active: tuner.detectedPitch > 0)

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 10)

                Circle()
                    .fill(indicatorColor)
                    .frame(width: 12, height: 12)
                    .offset(x: offset)
                    .animation(.easeOut(duration: 0.15), value: tuner.deviationCents)
            }
        }
        .frame(height: 12)
    }

    private func indicatorColor(for cents: Double, active: Bool) -> Color {
        guard active else { return Color.white.opacity(0.2) }
        let abs = Swift.abs(cents)
        if abs <= 5 { return .green }
        if abs <= 20 { return .yellow }
        return .red
    }

    // MARK: - String Selector

    private var stringSelector: some View {
        HStack(spacing: 4) {
            ForEach(GuitarString.allCases) { string in
                stringButton(string)
            }
            autoButton
        }
    }

    private func stringButton(_ string: GuitarString) -> some View {
        Button {
            if tuner.lockedString == string {
                tuner.lockedString = nil
            } else {
                tuner.lockedString = string
            }
        } label: {
            Text(string.displayName)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 28, height: 18)
                .foregroundStyle(tuner.lockedString == string ? Color.black : Color.white.opacity(0.4))
                .background(tuner.lockedString == string ? Color.yellow : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private var autoButton: some View {
        Button {
            tuner.lockedString = nil
        } label: {
            Text("Auto")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 28, height: 18)
                .foregroundStyle(tuner.lockedString == nil ? Color.black : Color.white.opacity(0.4))
                .background(tuner.lockedString == nil ? Color.yellow : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

}
