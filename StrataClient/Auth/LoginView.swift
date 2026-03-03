import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Strata").font(.largeTitle).fontWeight(.semibold)
            SecureField("Contraseña", text: $password)
                .frame(width: 280)
                .textFieldStyle(.roundedBorder)
            if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Button(action: attemptLogin) {
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("Entrar").frame(width: 80)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || isLoading)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(40)
        .frame(width: 360)
    }

    private func attemptLogin() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await auth.login(password: password)
            } catch {
                errorMessage = "Contraseña incorrecta"
            }
            isLoading = false
        }
    }
}
