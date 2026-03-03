import SwiftUI

@main
struct StrataApp: App {
    @State private var authViewModel: AuthViewModel
    @State private var libraryStore: LibraryStore
    @State private var importViewModel: ImportViewModel
    @State private var playbackEngine = PlaybackEngine()

    init() {
        let cacheManager = try! CacheManager()
        let auth = AuthViewModel()
        let store = LibraryStore(cacheManager: cacheManager)
        _authViewModel = State(initialValue: auth)
        _libraryStore = State(initialValue: store)
        _importViewModel = State(initialValue: ImportViewModel(
            apiClient: APIClient(),
            cacheManager: cacheManager,
            libraryStore: store,
            authViewModel: auth
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    ContentView()
                        .environment(libraryStore)
                        .environment(importViewModel)
                        .environment(playbackEngine)
                } else {
                    LoginView()
                }
            }
            .environment(authViewModel)
            .task {
                await libraryStore.loadFromDisk()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
    }
}
