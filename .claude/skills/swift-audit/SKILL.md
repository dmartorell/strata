---
name: swift-audit
description: >
  Audita código Swift/SwiftUI y genera un plan de refactorización priorizado con TODOs ejecutables.
  No toca código — solo diagnostica problemas, genera una tabla de prioridades y agrupa acciones por sesión.
  Úsalo siempre que el usuario quiera analizar, auditar o diagnosticar calidad de código Swift — ya sea macOS o iOS.
  Actívalo ante: "auditar código Swift", "analizar este archivo", "qué mejorarías", "diagnóstico SwiftUI",
  "revisar arquitectura", "este archivo es muy largo", "qué refactors harías", "problemas de rendimiento SwiftUI",
  o cuando el usuario comparta archivos .swift largos (>100 líneas) pidiendo feedback sobre estructura o calidad.
  También cuando mencione "spaghetti code", "vibe coding", o pida evaluar deuda técnica en una app Swift.
---

# Swift Audit

## Principio fundamental

**Lee antes de recetar.** Antes de diagnosticar o proponer cambios, lee la arquitectura existente del proyecto:

1. Lee `CLAUDE.md` del proyecto para entender convenciones, stack y restricciones
2. Lee el archivo de entrada de la app (`*App.swift`) para entender el grafo de dependencias
3. Identifica qué patrones ya están en uso antes de proponer nuevos

No propongas patrones que contradigan lo que el proyecto ya hace. Adapta tus recomendaciones a la arquitectura existente — no a una arquitectura ideal genérica.

---

## Proceso de análisis

### Fase 1: Diagnóstico

Identifica problemas concretos en el código recibido:

**Señales de alerta críticas:**
- Views con lógica de negocio (llamadas de red, persistencia, transformaciones de datos)
- Archivos monolíticos (>200 líneas en Views, >400 en ViewModels)
- Estado derivado recalculado en cada render del `body`
- Identidad inestable en `ForEach` (sin `.id()` explícito o usando índices)
- Animaciones que se disparan innecesariamente (sin `value:` parameter)
- `.onChange` redundantes o encadenados que disparan re-renders en cascada
- Código duplicado entre Views o ViewModels
- Anidamiento excesivo (>3-4 niveles) en el `body`

**Señales de advertencia:**
- `@State` usado para datos que deberían vivir en un ViewModel
- Funciones de más de 30 líneas
- Mezcla de lógica de presentación y dominio en el mismo scope
- Acceso directo a `UserDefaults`/`Keychain` desde Views

Comunica cada hallazgo con severidad: **[CRÍTICO]**, **[ADVERTENCIA]**, **[MENOR]**.

---

### Fase 2: Recomendaciones calibradas por contexto

La profundidad de la refactorización depende del proyecto:

#### Proyecto personal / MVP (1-2 devs, sin tests)
- Separar lógica de Views a ViewModels — esto es lo esencial
- Extraer subviews cuando un `body` supera ~80 líneas
- NO crear protocolos, repositories ni capas de abstracción innecesarias
- NO crear carpetas `Services/`, `Repositories/`, `Extensions/` si no hay masa crítica
- La simplicidad es más valiosa que la "arquitectura correcta"

#### Proyecto con equipo / producción
- Capas completas: Models, ViewModels, Services, Views
- Protocolos para testabilidad y desacoplamiento
- Dependency injection explícita

En caso de duda, elige la opción más simple que resuelva el problema.

---

### Fase 3: Patrones de refactorización

#### Extraer lógica a ViewModels

```swift
// ❌ Lógica en la View
struct SongListView: View {
    @State private var songs: [Song] = []
    @State private var isLoading = false

    var body: some View {
        List(songs) { song in /* ... */ }
        .task {
            isLoading = true
            let data = try? await URLSession.shared.data(from: url)
            songs = try! JSONDecoder().decode([Song].self, from: data!.0)
            isLoading = false
        }
    }
}

// ✅ Lógica en ViewModel
@Observable @MainActor
final class SongListViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // ...
    }
}

struct SongListView: View {
    @State private var vm = SongListViewModel()
    var body: some View {
        List(vm.songs) { song in /* ... */ }
        .task { await vm.load() }
    }
}
```

#### Extraer subviews para reducir archivos largos

```swift
// ❌ Body monolítico de 200+ líneas
var body: some View {
    VStack {
        HStack { /* 40 líneas de header */ }
        ScrollView { /* 100 líneas de contenido */ }
        HStack { /* 30 líneas de controles */ }
    }
}

// ✅ Componentes extraídos
var body: some View {
    VStack {
        HeaderBar(title: vm.title, onBack: handleBack)
        ContentScrollView(items: vm.items, currentItem: vm.current)
        ControlBar(isPlaying: vm.isPlaying, onToggle: vm.toggle)
    }
}
```

Preferir subviews como `struct` independientes que reciban datos por parámetros, no como `@ViewBuilder` privados (salvo que solo se usen internamente y sean cortos).

#### Cachear estado derivado costoso

```swift
// ❌ Recalcula en cada render
var body: some View {
    let filtered = items.filter { $0.isActive }.sorted(by: { $0.date > $1.date })
    ForEach(filtered) { item in /* ... */ }
}

// ✅ Cachear en el ViewModel, actualizar solo cuando cambie la fuente
@Observable @MainActor
final class ItemViewModel {
    var items: [Item] = [] { didSet { updateFiltered() } }
    private(set) var filtered: [Item] = []

    private func updateFiltered() {
        filtered = items.filter { $0.isActive }.sorted(by: { $0.date > $1.date })
    }
}
```

Para estado que no necesita disparar re-renders, usar `@ObservationIgnored`:

```swift
@ObservationIgnored private var lastIndex: Int = 0
```

---

### Fase 4: Rendimiento SwiftUI

Al refactorizar, verifica que no introduces regresiones de rendimiento:

#### Identidad estable en ForEach
```swift
// ❌ SwiftUI no puede diferenciar elementos eficientemente
ForEach(Array(items.enumerated()), id: \.offset) { ... }

// ✅ ID estable basada en el modelo
ForEach(items) { item in
    ItemRow(item: item).id(item.id)
}
```

#### Animaciones controladas
```swift
// ❌ Anima TODO lo que cambie — puede causar frames perdidos
.animation(.default)

// ✅ Anima solo el valor que importa
.animation(.easeInOut(duration: 0.3), value: currentItem?.id)
```

#### onChange eficiente
```swift
// ❌ Múltiples onChange que recalculan lo mismo
.onChange(of: a) { recompute() }
.onChange(of: b) { recompute() }
.onChange(of: c) { recompute() }

// ✅ Consolidar si comparten lógica, o al menos evitar trabajo redundante
.onChange(of: a) { _, _ in recompute() }
.onChange(of: b) { _, _ in recompute() }
```

#### Timer/tick patterns
```swift
// ❌ @Published que dispara re-render en cada frame
@Published var currentTime: Double = 0  // 60 veces/segundo

// ✅ Callback pattern — solo actualiza lo que necesita cambiar
@ObservationIgnored var onTick: (() -> Void)?
// El ViewModel decide qué propiedades observables actualizar
```

---

### Fase 5: Plan de refactorización

Después del diagnóstico, genera **siempre**:

#### 5a — Tabla de refactors ordenada por impacto

Cada fila debe dar suficiente contexto para que un agente que no ha visto el código pueda entender **qué** hay que hacer, **dónde** y **cómo**. La columna "Acción" es la clave — debe ser una instrucción ejecutable, no una etiqueta vaga.

| # | Prioridad | Archivo(s) | Problema | Acción | Esfuerzo |
|---|-----------|------------|----------|--------|----------|

Ejemplo de fila bien escrita:

| 1 | CRÍTICO | `PlayerView.swift` (L45-120) | 75 líneas de lógica de carga y transformación de datos en `.task {}` | Extraer a `PlayerViewModel.loadSong()` async. Mover los @State de `lyrics`, `chords`, `isLoading` al VM. La View solo llama `.task { await vm.loadSong() }` y observa el VM | M |

Ejemplo de fila mal escrita:

| 1 | CRÍTICO | `PlayerView.swift` | Demasiada lógica | Refactorizar | M |

**Criterios para la columna "Acción":**
- Nombrar los métodos/propiedades a crear o mover
- Indicar el archivo destino si es nuevo
- Mencionar el patrón a usar (`@Observable`, `@ObservationIgnored`, actor, etc.)
- Si hay que extraer subviews, indicar qué rango de líneas va a cada componente

**Esfuerzo:** S = <1h · M = 1-3h · L = 3-8h

**Prioridad:**
- **CRÍTICO** — Causa bugs, problemas de rendimiento, o bloquea nuevas features
- **MEDIO** — Deuda técnica que ralentiza el desarrollo
- **MENOR** — Mejora de legibilidad, bajo riesgo si se pospone

#### 5b — TODOs agrupados por sesión

Cada TODO debe contener la información mínima para que un agente pueda ejecutarlo **sin preguntar nada** y **sin leer todo el archivo** — solo las líneas relevantes.

```
## SESIÓN 1 — [nombre descriptivo]
Contexto: [1-2 frases: qué archivos se tocan, por qué empezar aquí, y qué patrón del proyecto seguir como referencia]

TODO 1: Crear `ViewModels/SongListViewModel.swift`
- Clase `@Observable @MainActor final class SongListViewModel`
- Mover `@State var songs`, `@State var isLoading`, `@State var error` desde `SongListView.swift` (L12-14)
- Mover el bloque `.task {}` de `SongListView.swift` (L45-67) a método `func load() async`
- Exponer propiedades como `private(set) var`

TODO 2: Actualizar `SongListView.swift`
- Reemplazar los 3 @State (L12-14) por `@State private var vm = SongListViewModel()`
- Reemplazar `.task { ... }` (L45-67) por `.task { await vm.load() }`
- Cambiar referencias: `songs` → `vm.songs`, `isLoading` → `vm.isLoading`

Archivos a modificar: SongListView.swift (L12-14, L45-67)
Archivos a crear: ViewModels/SongListViewModel.swift
PRECAUCIÓN: SongListView usa `@Environment(LibraryStore.self)` en L8 — el VM también necesitará recibirlo por init o environment
```

Reglas:
- Cada TODO indica líneas concretas (L45-67) cuando sea posible — el agente no debería tener que buscar
- Nombrar las propiedades, métodos y tipos exactos a crear/mover
- Si el TODO depende de un patrón existente en el proyecto, indicar qué archivo usar como referencia (ej: "seguir el patrón de `PlayerViewModel.swift`")
- Sesiones independientes entre sí — se pueden ejecutar en cualquier orden
- Si hay dependencias dentro de una sesión, numerar en orden de ejecución

#### 5c — Confirmación

> "¿Empiezo con la Sesión 1 o prefieres ajustar algo?"

No tocar código hasta que el usuario confirme.

---

### Orden de entrega

1. **Diagnóstico** con severidades
2. **Tabla de refactors**
3. **TODOs por sesión**
4. **Confirmación**
5. **Código** solo tras confirmación

---

## Checklist post-refactorización

Antes de presentar el resultado:

- [ ] Ninguna View ejecuta lógica de negocio, red o persistencia
- [ ] Cada archivo tiene una responsabilidad clara
- [ ] No hay lógica duplicada
- [ ] ForEach usa identidad estable (no índices)
- [ ] Las animaciones tienen `value:` explícito
- [ ] Estado derivado costoso está cacheado, no recalculado en `body`
- [ ] No se introdujeron abstracciones innecesarias (protocolos, capas, helpers) para el tamaño del proyecto
- [ ] Los patrones nuevos son consistentes con los patrones existentes del proyecto

---

## Notas

- **Swift concurrency**: Preferir `async/await` sobre completion handlers
- **macOS vs iOS**: Ambas plataformas comparten SwiftUI pero difieren en controles (Table vs List, menús contextuales, window management). Adaptar las recomendaciones a la plataforma del proyecto
- **@Observable vs ObservableObject**: Usar `@Observable` para macOS 14+ / iOS 17+. Solo `ObservableObject` si el target es anterior
- **No sobre-arquitecturizar**: La complejidad mínima para resolver el problema es la cantidad correcta

Consulta `references/swift-patterns.md` para ejemplos de patrones específicos.
