# Persistent Playback — Diseño

**Fecha:** 2026-03-25
**Enfoque elegido:** Elevar PlayerViewModel a ContentView

## Resumen

Mantener la canción activa sonando mientras el usuario navega de vuelta a la biblioteca. Un mini-player floating bottom-left permite ver qué suena y volver al player completo. Al regresar a la canción activa, la UI se reconecta al estado exacto (minutaje, lyrics highlight, etc).

## Arquitectura de estado

### ContentView asume ownership del PlayerViewModel

- `@State playerVM: PlayerViewModel?` se eleva de PlayerView a ContentView
- `PlayerView` recibe el VM como parámetro en vez de crearlo internamente
- `PlaybackEngine` ya vive en `SiyahambaApp` — sin cambios

### Flujo de vida del PlayerViewModel

| Evento | Acción |
|--------|--------|
| Seleccionar canción (sin VM activo) | Crear nuevo VM, `load()`, asignar a `playerVM` |
| Seleccionar la **misma** canción activa | Reasignar `selectedSong` → PlayerView se monta, reutiliza VM existente |
| Seleccionar canción **diferente** (con VM activo) | `fadeOutAndStop()` + crear nuevo VM (stop + load) |
| Back a biblioteca | `selectedSong = nil`, audio sigue, mini-player aparece |
| Detener explícitamente | `fadeOutAndStop()` + `playerVM = nil` + `selectedSong = nil` |

### Carga del VM (en ContentView)

Se usa `.onChange(of: selectedSong?.id)`:
- Si es la misma canción activa → no hacer nada (reconectar)
- Si es diferente → stop canción anterior + crear nuevo VM + load

### Guardado de preferencias

- `savePitchOffset()` y `saveDisplayMode()` se llaman antes de `selectedSong = nil` (back normal)
- También se llaman antes de `fadeOutAndStop()` al cambiar de canción

## Mini-player: NowPlayingBar

### Posición
Overlay floating bottom-left en ContentView, visible cuando `playerVM != nil` y `selectedSong == nil`.

### Contenido
- Icono play/pause — toggle directo sobre engine
- Título + artista
- Tiempo actual formateado
- Barra de progreso visual (sin seek)
- Botón expandir (`chevron.up`) — asigna `selectedSong = playerVM.song`

### Estilo
- Fondo con `VisualEffectView` (blur) + borde sutil
- Corner radius, ancho fijo ~300pt
- Padding 12pt respecto al borde de la ventana

## Reconexión al volver al player

No requiere código especial:
1. `selectedSong = playerVM!.song` → PlayerView se monta
2. PlayerView recibe el VM existente con lyrics, chords, engine en curso
3. `LyricsView` lee `engine.currentTime` vía computed properties → se sincroniza automáticamente
4. El scroll se posiciona vía `onChange(of: vm.currentLine?.id)` ya existente

## Archivos a modificar

| Archivo | Cambio |
|---------|--------|
| `ContentView.swift` | Añadir `@State playerVM`, `onChange` para load, overlay mini-player |
| `PlayerView.swift` | Recibir `playerVM` externo, eliminar `.task { load() }`, simplificar back |

## Componente nuevo

| Archivo | Descripción |
|---------|-------------|
| `NowPlayingBar.swift` | Mini-player floating (~80 líneas) |

## Archivos sin cambios

- `PlaybackEngine.swift`, `LyricsView.swift`, `TransportBarView.swift`, `SiyahambaApp.swift`, `LibraryView.swift`

## Orden de implementación

1. Modificar PlayerView — aceptar `playerVM` externo
2. Modificar ContentView — elevar VM, gestionar load/back
3. Crear NowPlayingBar
4. Conectar overlay en ContentView
5. Testing manual: play → back → mini-player → expandir → lyrics sincronizadas
