# Swift Patterns Reference

Patrones comunes para refactorizar código Swift/SwiftUI.

---

## Dependency Injection con @Environment

```swift
// Crear dependencias en el App entry point
@main
struct MyApp: App {
    @State private var authVM = AuthViewModel()
    @State private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authVM)
                .environment(store)
        }
    }
}

// Consumir en Views
struct SomeView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(LibraryStore.self) private var store
    // ...
}
```

Para tipos que no son `@Observable`, usar custom EnvironmentKey:

```swift
private struct CacheManagerKey: EnvironmentKey {
    static let defaultValue: CacheManager? = nil
}

extension EnvironmentValues {
    var cacheManager: CacheManager? {
        get { self[CacheManagerKey.self] }
        set { self[CacheManagerKey.self] = newValue }
    }
}

// Inyectar: .environment(\.cacheManager, myCacheManager)
// Consumir: @Environment(\.cacheManager) private var cacheManager
```

---

## ViewModel con @Observable + @MainActor

```swift
@Observable @MainActor
final class PlayerViewModel {
    private(set) var currentLine: LyricLine? = nil
    private(set) var isPlaying = false

    // Estado que no necesita disparar re-renders
    @ObservationIgnored private var lastIndex: Int = 0

    private let engine: PlaybackEngine

    init(engine: PlaybackEngine) {
        self.engine = engine
    }

    func play() async { /* ... */ }
}
```

---

## Tick/Callback Pattern para actualizaciones de alta frecuencia

Cuando un engine actualiza estado a 60fps, no exponer cada cambio como propiedad observable. Usar callbacks para que el ViewModel decida qué propiedades actualizar:

```swift
// En el Engine
@Observable @MainActor
final class PlaybackEngine {
    @ObservationIgnored var onTick: (() -> Void)?
    private(set) var currentTime: Double = 0

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016) { [weak self] _ in
            self?.currentTime = self?.playerNode.currentTime ?? 0
            self?.onTick?()
        }
    }
}

// En el ViewModel — actualiza solo lo necesario
func tick() {
    let time = engine.currentTime
    updateCurrentLine(at: time)   // Solo cambia currentLine si realmente cambió
    updateCurrentChord(at: time)  // Búsqueda binaria con cache de último índice
}
```

---

## Cachear estado derivado

```swift
@Observable @MainActor
final class ListViewModel {
    var items: [Item] = [] {
        didSet { recalculate() }
    }
    var filter: Filter = .all {
        didSet { recalculate() }
    }

    private(set) var filteredItems: [Item] = []

    private func recalculate() {
        filteredItems = items.filter { filter.matches($0) }
    }
}
```

---

## Navegación simple con estado

Para apps con pocas pantallas, navegación basada en estado es más simple que `NavigationStack`:

```swift
struct ContentView: View {
    @State private var selectedSong: SongEntry?

    var body: some View {
        Group {
            if let song = selectedSong {
                PlayerView(song: song, onBack: { selectedSong = nil })
            } else {
                LibraryView(onSongSelected: { selectedSong = $0 })
            }
        }
    }
}
```

---

## Networking con APIClient

```swift
protocol APIClientProtocol {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
}

final class APIClient: APIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: AuthTokenProviderProtocol?

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        var request = endpoint.urlRequest(baseURL: baseURL)
        if let token = tokenProvider?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

---

## Extraer subviews con datos por parámetros

```swift
// Subview que recibe datos — sin acceder al ViewModel directamente
struct LyricLineView: View {
    let line: LyricLine
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Text(line.text)
            .fontWeight(isCurrent ? .bold : .regular)
            .opacity(isCurrent ? 1.0 : 0.5)
            .onTapGesture(perform: onTap)
    }
}

// Uso desde la View padre
ForEach(vm.lyrics) { line in
    LyricLineView(
        line: line,
        isCurrent: line.id == vm.currentLine?.id,
        onTap: { vm.seek(to: line.start) }
    )
    .id(line.id)
}
```

---

## Thread-safe file I/O con Actor

```swift
actor CacheManager {
    private let baseURL: URL

    func save(_ data: Data, as filename: String) throws {
        let fileURL = baseURL.appending(component: filename)
        try data.write(to: fileURL)
    }

    func load(_ filename: String) throws -> Data {
        let fileURL = baseURL.appending(component: filename)
        return try Data(contentsOf: fileURL)
    }
}
```

---

## Error Handling en ViewModels

```swift
@Observable @MainActor
final class SomeViewModel {
    var error: AppError?

    func doWork() async {
        do {
            // ...
        } catch {
            self.error = AppError(error)
        }
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String
    init(_ error: Error) { self.message = error.localizedDescription }
}

// En la View
.alert(item: $vm.error) { error in
    Alert(title: Text("Error"), message: Text(error.message))
}
```
