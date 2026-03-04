import SwiftUI

struct UsageView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var usage: UsageData?
    @State private var loadError: Bool = false

    var body: some View {
        Group {
            if let u = usage {
                VStack(spacing: 4) {
                    let costText = String(format: "%.2f", u.estimatedCostEur)
                    Text("\(u.songsProcessed) canciones este mes · ~€\(costText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let progress = u.spendingLimitUsd > 0 ? u.estimatedCostUsd / u.spendingLimitUsd : 0
                    ProgressView(value: u.estimatedCostUsd, total: max(u.spendingLimitUsd, 0.01))
                        .tint(progress > 0.8 ? .orange : .accentColor)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
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
