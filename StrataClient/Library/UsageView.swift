import SwiftUI

struct UsageView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var usage: UsageData?
    @State private var loadError: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            if let u = usage {
                let costText = String(format: "%.2f", u.estimatedCostEur)
                Text("\(u.songsProcessed) canciones este mes (€\(costText) aprox)")
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
        .task { await fetchUsage() }
    }

    private func fetchUsage() async {
        guard let token = auth.token else { return }
        do {
            usage = try await APIClient().fetchUsage(token: token)
        } catch {
            loadError = true
        }
    }
}
