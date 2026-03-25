import SwiftUI

private struct CacheManagerKey: EnvironmentKey {
    static let defaultValue: CacheManager? = nil
}

extension EnvironmentValues {
    var cacheManager: CacheManager? {
        get { self[CacheManagerKey.self] }
        set { self[CacheManagerKey.self] = newValue }
    }
}

@main
struct SiyahambaApp: App {
    @State private var authViewModel: AuthViewModel
    @State private var libraryStore: LibraryStore
    @State private var importViewModel: ImportViewModel
    @State private var playbackEngine: PlaybackEngine
    @State private var tunerEngine: TunerEngine
    @State private var cacheManager: CacheManager

    init() {
        let cm = try! CacheManager()
        let auth = AuthViewModel()
        let store = LibraryStore(cacheManager: cm)
        let pe = PlaybackEngine()
        _authViewModel = State(initialValue: auth)
        _libraryStore = State(initialValue: store)
        _cacheManager = State(initialValue: cm)
        _playbackEngine = State(initialValue: pe)
        _tunerEngine = State(initialValue: TunerEngine(playbackEngine: pe))
        _importViewModel = State(initialValue: ImportViewModel(
            apiClient: APIClient(),
            cacheManager: cm,
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
                        .environment(tunerEngine)
                        .environment(\.cacheManager, cacheManager)
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
