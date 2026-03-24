import SwiftUI

struct UsageView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var usage: UsageData?
    @State private var loadError: Bool = false
    @State private var refreshID = UUID()

    var body: some View {
        VStack(spacing: 4) {
            if let u = usage {
                let remaining = String(format: "%.2f", u.creditRemainingEur)
                Text("Crédito: €\(remaining)")
                    .font(.caption)
                    .foregroundStyle(creditColor(for: u))
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

    private func creditColor(for u: UsageData) -> Color {
        guard u.monthlyCreditUsd > 0 else { return .secondary }
        let ratio = u.creditRemainingUsd / u.monthlyCreditUsd
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .yellow }
        return .red
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
