import SwiftUI

@main
struct StrataApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var libraryStore: LibraryStore
    @State private var playbackEngine = PlaybackEngine()

    init() {
        // try! es aceptable: si ~/Music no es accesible la app no puede funcionar
        let cacheManager = try! CacheManager()
        _libraryStore = State(initialValue: LibraryStore(cacheManager: cacheManager))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    ContentView()
                        .environment(libraryStore)
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
