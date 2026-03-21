import SwiftUI

struct UsageView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var usage: UsageData?
    @State private var loadError: Bool = false
    @State private var refreshID = UUID()

    var body: some View {
        VStack(spacing: 4) {
            if let u = usage {
                let costText = String(format: "%.2f", u.estimatedCostEur)
                let songWord = u.songsProcessed == 1 ? "canción" : "canciones"
                Text("\(u.songsProcessed) \(songWord) este mes · €\(costText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !loadError {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task(id: refreshID) { await fetchUsage() }
        .onAppear { refreshID = UUID() }
    }

    private func fetchUsage() async {
        usage = nil
        loadError = false
        guard let token = auth.token else { return }
        do {
            usage = try await APIClient().fetchUsage(token: token)
        } catch {
            loadError = true
        }
    }
}
