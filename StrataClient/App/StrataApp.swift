import SwiftUI

@main
struct StrataApp: App {
    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if authViewModel.isAuthenticated {
                ContentView()
                    .environment(authViewModel)
            } else {
                LoginView()
                    .environment(authViewModel)
            }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}
