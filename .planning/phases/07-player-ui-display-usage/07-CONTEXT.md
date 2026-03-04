# Phase 7: Player UI + Display + Usage - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

El usuario controla la reproduccion desde la UI, ve letras sincronizadas palabra a palabra, acordes en tiempo real, waveforms por stem, secciones, y consulta su consumo mensual de GPU. La biblioteca muestra metadatos y permite seleccion multiple + eliminar. El pitch offset se persiste por cancion entre sesiones.

</domain>

<decisions>
## Implementation Decisions

### Letras (Karaoke)
- Scroll vertical centrado: linea actual en el medio de la pantalla, 2-3 lineas de contexto arriba y abajo con opacidad reducida
- Resaltado palabra a palabra con color de acento + negrita sobre la palabra que suena
- Solo visual — sin click-to-seek en las lineas de la letra
- Al hacer seek o cambiar pitch, las letras saltan al punto correcto

### Acordes
- Acorde actual en texto grande + siguiente acorde visible mas pequeno (sin countdown)
- Notacion anglosajona siempre (Am, G7, Bb, C#m7)
- Toggle original/transpuesto: cuando hay pitch shift, el usuario puede alternar entre acordes originales y acordes transpuestos al tono actual
- Solo nombre del acorde en v1, sin diagramas de posicion de dedos

### Layout del reproductor (modelo Moises)
- Sidebar izquierda siempre visible con controles de stem: boton M (mute), boton S (solo), slider de volumen. Sin pan. Orden fijo: Voz, Bateria, Bajo, Otro
- Zona principal es modal, cambia segun toggles activos en barra inferior:
  - Nada activo → waveforms por pista a pantalla completa, voz siempre arriba, playhead vertical
  - Letras ON → waveforms desaparecen, letras grandes centradas con scroll sincronizado
  - Letras + Acordes ON → stack vertical: letras arriba, separador, acordes abajo
  - Solo Acordes ON → acordes a pantalla completa (en v2 con diagramas de guitarra)
  - Secciones ON → vista de secciones (verso, estribillo, etc.) detectadas del audio
- Barra inferior fija: controles de transporte (volumen, rew, play/pause, fwd, loop) + progress bar con timestamps + toggles (Letras, Acordes, Secciones)
- Barra superior: flecha atras (vuelve a biblioteca), titulo cancion, boton pitch (muestra nota actual), boton A/B loop
- Pitch popover al pulsar boton pitch: nota grande en el centro, botones −/+, afinacion Hz, boton restablecer
- Al pulsar una cancion en la biblioteca, la vista de biblioteca se reemplaza por la vista de reproductor completa
- Esquema de color: seguir modo del sistema macOS (light/dark), no forzar oscuro
- Waveforms con color unico para todas las pistas (Claude elige el color)

### Biblioteca
- Vista de tabla con columnas: Titulo, Artista, Tono, Duracion
- Seleccion multiple + boton eliminar (borra del cache local)
- Tono original de la cancion: inferir heuristicamente del acorde mas frecuente en chords.json (sin cambio en server)
- Pitch offset persistido por cancion entre sesiones: al reabrir una cancion, el pitch slider recuerda la ultima posicion

### Panel de uso
- Resumen compacto siempre visible en la vista de biblioteca (parte inferior o superior)
- Formato: "N canciones este mes · ~€X.XX"
- Conversion USD→EUR con tipo de cambio fijo hardcodeado (~0.92 EUR/USD)
- Al recibir 429 del server: banner inline en la zona de importacion, sin bloquear la UI. El usuario puede seguir reproduciendo canciones ya procesadas

### Claude's Discretion
- Diseno del loading skeleton para waveforms
- Espaciado y tipografia exactos
- Color de las waveforms
- Posicion exacta del panel de acordes respecto a las letras en modo stack
- Algoritmo para inferir tono original (acorde mas frecuente vs primer acorde vs heuristica musical)
- Implementacion de la vista de secciones
- Transiciones/animaciones entre modos (waveforms ↔ letras ↔ acordes)

</decisions>

<specifics>
## Specific Ideas

- Referencia visual principal: **Moises app** — layout de sidebar + zona modal + toggles inferiores
- Imagen 1 (waveforms): 4 pistas con waveform, voz arriba, playhead vertical, controles M/S + volumen en sidebar izquierda
- Imagen 2 (letras): misma sidebar, zona principal muestra letras grandes con lineas en opacidad reducida para contexto
- Imagen 3 (letras + acordes): stack vertical con letras arriba y acordes abajo (F, Cbm, Bb como timeline horizontal)
- Imagen 4 (solo acordes): acordes con diagramas de guitarra — solo nombres en v1, diagramas en v2
- Imagen 5 (pitch popover): boton en toolbar muestra nota actual "F", al desplegar: "Tono de la cancion", afinacion Hz, botones −/+, restablecer
- Biblioteca tipo tabla como Moises: Titulo, Artista, Tono, Duracion — sin BPM ni Genero (no disponibles en pipeline actual)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PlaybackEngine` (@Observable, @MainActor): ya tiene play/pause/stop/seek, pitch shift (setPitch), A/B loop, per-stem volume/mute/solo, currentTime publisher a 60fps — es la base completa para la UI de transporte
- `CacheManager` (actor): proporciona lyricsURL(songID:) y chordsURL(songID:) para leer lyrics.json y chords.json del cache local
- `SongEntry` (Codable): tiene id, title, artist, duration, sourceURL, fileName, sourceHash, addedAt — necesita ampliarse con pitchOffset y key
- `SongMetadata` (Codable): title, artist, durationSeconds, sampleRate, sourceType, processedAt, originalFilename
- `LibraryStore` (@Observable): gestiona la lista de canciones, conectado via @Environment
- `ContentView`: actualmente muestra ImportView + lista simple de canciones — sera reemplazado/ampliado con la tabla y navegacion al reproductor

### Established Patterns
- @Observable + @Environment para estado compartido (LibraryStore, ImportViewModel, PlaybackEngine)
- Actor isolation para I/O (CacheManager)
- SwiftUI declarativo con ViewBuilder para composicion
- Timer a 60fps para currentTime updates en PlaybackEngine

### Integration Points
- ContentView.songRow → debe convertirse en tabla con columnas y seleccion multiple
- ContentView → nueva navegacion: click en cancion abre PlayerView que reemplaza la vista
- PlaybackEngine.currentTime → alimenta LyricsView y ChordView para sincronizacion
- PlaybackEngine.pitchSemitones → alimenta transposicion de acordes y popover de pitch
- GET /usage (server) → UsageView en biblioteca, ya devuelve songs_processed, gpu_seconds, estimated_cost_usd, spending_limit_usd
- Server 429 response → ImportViewModel debe capturar y mostrar banner

</code_context>

<deferred>
## Deferred Ideas

- Diagramas de posicion de dedos en vista de acordes — v2 (DISP con diagramas de guitarra)
- BPM y Genero como columnas en biblioteca — requiere datos del pipeline no disponibles actualmente
- Click-to-seek en lineas de letra — evaluable en v2
- Barrido progresivo tipo Apple Music para resaltado de palabras — v2 (v1 usa color+negrita)

</deferred>

---

*Phase: 07-player-ui-display-usage*
*Context gathered: 2026-03-04*
