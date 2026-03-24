# Roadmap: Strata

## Overview

El proyecto arranca con el backend serverless (Modal GPU), que es la dependencia raiz de todo. Una vez el pipeline de IA esta probado en hardware real, se construye el cliente Swift desde la capa de red hacia arriba: auth, cache, motor de audio, flujo de importacion y, finalmente, la interfaz de reproduccion con letras, acordes y panel de uso.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Backend Foundation** - Modal API deployada con auth JWT, endpoints stub y contratos reales
- [x] **Phase 2: GPU Pipeline** - Demucs + WhisperX + CREMA corriendo en T4 con cold-start dentro de presupuesto (completed 2026-03-02)
- [x] **Phase 3: Swift Client + Auth** - Cliente Swift con URLSession, JWT en Keychain y pantalla de login (completed 2026-03-03)
- [x] **Phase 4: Library + Cache** - Cache local ~/Music/Strata/ con schema fijo antes de persistir canciones (completed 2026-03-03)
- [x] **Phase 5: Multi-Stem Playback** - AVAudioEngine con sync frame-accurate, pitch shift y controles de stem (completed 2026-03-03)
- [x] **Phase 6: Import + End-to-End Flow** - Drag & drop, URL de YouTube y UI de progreso conectados al pipeline (completed 2026-03-03)
- [ ] **Phase 7: Player UI + Display + Usage** - Controles de reproduccion, karaoke, acordes y panel de uso

## Phase Details

### Phase 1: Backend Foundation
**Goal**: La API Modal esta desplegada y accesible via HTTPS; el cliente Swift puede autenticarse y recibir respuestas reales (aunque con datos stub) sin tocar localhost
**Depends on**: Nothing (first phase)
**Requirements**: INFR-01, INFR-02, INFR-03, INFR-04
**Success Criteria** (what must be TRUE):
  1. Un curl al endpoint `/auth/login` con contrasena correcta devuelve un JWT valido firmado con PyJWT
  2. Un curl con JWT invalido o ausente a cualquier endpoint protegido devuelve 401
  3. El endpoint `/process` (stub) acepta un archivo y devuelve un job ID sin procesar nada real
  4. El endpoint `/result/{id}` devuelve un payload de ejemplo con estructura final (stems, lyrics, chords) aunque sean datos ficticios
  5. La imagen Modal tiene los pesos de los modelos baked in y el contenedor arranca en <15s en cold start
**Plans**: TBD

Plans:
- [ ] 01-01: Modal app setup, FastAPI skeleton, `/auth/login` con PyJWT + bcrypt, usuarios hardcoded
- [ ] 01-02: Endpoints `/process` (stub) y `/result/{id}`, validacion JWT en middleware, limites de concurrencia
- [ ] 01-03: Modal image con CUDA 12.8, placeholder de pesos, cold-start medido y documentado

### Phase 2: GPU Pipeline
**Goal**: Un archivo de audio real entra al pipeline y sale un ZIP con 4 stems WAV + lyrics.json + chords.json + metadata.json dentro del presupuesto de tiempo
**Depends on**: Phase 1
**Requirements**: PROC-01, PROC-02, PROC-03, PROC-04, PROC-05, PROC-06, PROC-07, PROC-08
**Success Criteria** (what must be TRUE):
  1. Un archivo MP3 de 3 minutos procesado devuelve 4 stems WAV separados (vocals, drums, bass, other) correctamente
  2. El JSON de letras contiene timestamps word-level (WhisperX sobre el stem vocal, no el mix original)
  3. El JSON de acordes contiene una lista de acordes con timestamps producida por CREMA (o madmom como fallback)
  4. El pipeline completo para un archivo local termina en <60 segundos desde la llamada al endpoint
  5. Una URL de YouTube valida se descarga y procesa en <65 segundos en total
  6. Archivos >50 MB o duracion >10 min son rechazados con error claro antes de arrancar la GPU
**Plans**: TBD

Plans:
- [ ] 02-01: Modal image con Demucs 4.0.1, pesos baked, `@modal.enter` warm-up, test de separacion real en T4
- [ ] 02-02: WhisperX 3.8.1 (CUDA 12.8) integrado sobre stem vocal; validacion de timestamps word-level
- [ ] 02-03: CREMA 0.2.0 (fallback madmom), validacion de Python 3.11, test de compatibilidad antes de integrar
- [ ] 02-04: yt-dlp + Deno en imagen, cookies via Modal Secret, retry logic (3 intentos), test con URLs reales
- [ ] 02-05: Empaquetado ZIP final (4 WAV + JSONs), validacion de limites (50 MB / 10 min), medicion de cold-start total

### Phase 3: Swift Client + Auth
**Goal**: La app Swift puede autenticarse, almacenar el JWT en Keychain y comunicarse con todos los endpoints de la API sin tocar codigo de red en fases posteriores
**Depends on**: Phase 1
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04
**Success Criteria** (what must be TRUE):
  1. El usuario introduce la contrasena una vez, inicia sesion y la app no vuelve a pedir login durante 90 dias
  2. Al abrir la app con sesion vigente, el token se lee del Keychain y no se muestra la pantalla de login
  3. Cuando el token esta proximo a expirar, se renueva silenciosamente sin interrupcion visible para el usuario
  4. Si el token ha expirado, la app redirige automaticamente a la pantalla de login sin crashear
**Plans**: 3 plans

Plans:
- [ ] 03-01-PLAN.md — Proyecto Xcode macOS + APIClient completo (URLSession, multipart, polling, error types)
- [ ] 03-02-PLAN.md — KeychainService (Security.framework) + endpoint POST /auth/renew en servidor
- [ ] 03-03-PLAN.md — AuthViewModel (@Observable) + LoginView + StrataApp root auth gate

### Phase 4: Library + Cache
**Goal**: Las canciones procesadas se persisten en ~/Music/Strata/ con un schema que no necesitara migracion; canciones ya cacheadas cargan sin tocar el servidor
**Depends on**: Phase 3
**Requirements**: LIBR-01, LIBR-02
**Success Criteria** (what must be TRUE):
  1. Una cancion procesada aparece en ~/Music/Strata/{uuid}/ con 4 stems WAV, lyrics.json, chords.json y metadata.json
  2. Al abrir la app con canciones en cache, la biblioteca carga instantaneamente sin peticion al servidor
  3. Si la misma URL de YouTube o el mismo archivo ya esta en cache, la app detecta el hit y no vuelve a procesar
**Plans**: 2 plans

Plans:
- [ ] 04-01-PLAN.md — SongEntry + SongMetadata (Codable), CacheManager (actor, I/O atomico), LibraryStore (@Observable)
- [ ] 04-02-PLAN.md — SHA256 incremental, YouTube video ID extractor, materializeSong, wiring LibraryStore en StrataApp

### Phase 5: Multi-Stem Playback
**Goal**: Los 4 stems suenan perfectamente sincronizados; el usuario puede controlar cada stem y cambiar el tono en tiempo real sin interrumpir la reproduccion
**Depends on**: Phase 4
**Requirements**: PLAY-01, PLAY-02, PLAY-03, PLAY-04, PLAY-05, PLAY-06
**Success Criteria** (what must be TRUE):
  1. Los 4 stems arrancan en el mismo instante (sin drift audible tras 5 minutos de reproduccion)
  2. Silenciar o subir el volumen de un stem no afecta a los demas ni produce artefactos de audio
  3. El usuario puede cambiar el tono en tiempo real (slider) sin que la reproduccion se detenga ni cruja
  4. El usuario puede saltar a cualquier posicion de la cancion y la reproduccion continua sincronizada desde ese punto
  5. El usuario puede definir marcadores A/B y la seccion se repite en bucle automaticamente
**Plans**: TBD

Plans:
- [ ] 05-01: PlaybackEngine (@Observable), AVAudioEngine + 4x AVAudioPlayerNode, shared AVAudioTime para sync frame-accurate
- [ ] 05-02: AVAudioUnitTimePitch (debounced 50ms), per-stem volume/mute/solo, seek con re-schedule sincronizado
- [ ] 05-03: A/B loop markers, currentTime publisher para consumo de Display, tests de no-drift a 5 min

### Phase 6: Import + End-to-End Flow
**Goal**: El usuario arrastra un archivo o pega una URL y ve el progreso paso a paso hasta que la cancion aparece en la biblioteca lista para reproducir
**Depends on**: Phase 5
**Requirements**: IMPT-01, IMPT-02, IMPT-03, IMPT-04
**Success Criteria** (what must be TRUE):
  1. El usuario arrastra un MP3/WAV/FLAC/M4A a la app y el proceso arranca automaticamente sin pasos extra
  2. El usuario pega una URL de YouTube y el proceso arranca tras validar que la URL es valida
  3. La app muestra el estado en tiempo real: validando → subiendo → procesando → listo (o error con mensaje util)
  4. Una cancion ya procesada importada de nuevo no dispara el pipeline; la app detecta el cache hit y abre la cancion directamente
**Plans**: 3 plans

Plans:
- [ ] 06-01-PLAN.md — APIClient corregido (/process-file, /process-url, ZIP detection) + ImportPhase enum + ImportViewModel con flujo completo
- [ ] 06-02-PLAN.md — ImportView (drop zone + paste button + progress UI) + ContentView layout + StrataApp wiring
- [ ] 06-03-PLAN.md — APIClientProtocol + tests de ImportViewModel (cache hits, errores, flujo end-to-end)

### Phase 7: Player UI + Display + Usage
**Goal**: El usuario puede controlar la reproduccion desde la UI, ver las letras sincronizadas palabra a palabra, los acordes en tiempo real y consultar cuanto GPU ha consumido este mes
**Depends on**: Phase 6
**Requirements**: DISP-01, DISP-02, DISP-03, DISP-04, DISP-05, USGR-01, USGR-02, USGR-03, USGR-04
**Success Criteria** (what must be TRUE):
  1. Las letras se desplazan automaticamente y la palabra actual se resalta mientras suena; al hacer seek las letras saltan al punto correcto
  2. El acorde actual se muestra en grande y el siguiente acorde aparece visible antes de que llegue
  3. La visualizacion de acordes y letras actualiza correctamente al cambiar el tono con el pitch slider
  4. La forma de onda de cada stem es visible en la UI de reproduccion
  5. El panel de uso muestra canciones procesadas este mes, coste GPU estimado y barra de progreso hacia el limite de $10
  6. El servidor devuelve 429 cuando se alcanza el limite mensual y la app lo comunica al usuario con mensaje claro
**Plans**: 5 plans

Plans:
- [x] 07-01-PLAN.md — Modelos de datos (Lyrics, Chords, ChordTransposer), SongEntry extension, DSWaveformImage, APIClient.fetchUsage
- [x] 07-02-PLAN.md — Server 429 limit check + cliente captura 429 en ImportViewModel
- [x] 07-03-PLAN.md — PlayerViewModel, ContentView navegacion, LibraryView tabla, UsageView panel
- [x] 07-04-PLAN.md — PlayerView layout (sidebar stems, transport bar, pitch popover, waveforms)
- [x] 07-05-PLAN.md — LyricsView karaoke + ChordView + integracion zona principal modal

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Backend Foundation | 2/3 | In Progress|  |
| 2. GPU Pipeline | 5/5 | Complete   | 2026-03-02 |
| 3. Swift Client + Auth | 3/3 | Complete   | 2026-03-03 |
| 4. Library + Cache | 2/2 | Complete   | 2026-03-03 |
| 5. Multi-Stem Playback | 3/3 | Complete   | 2026-03-03 |
| 6. Import + End-to-End Flow | 3/3 | Complete   | 2026-03-03 |
| 7. Player UI + Display + Usage | 5/5 | Complete   | 2026-03-05 |
| 8. YouTube Download Client-Side | 0/? | Not Started|  |
| 9. Chord Finger Position Diagrams | 2/2 | Complete   | 2026-03-24 |

### Phase 8: YouTube Download Client-Side
**Goal**: La descarga de audio de YouTube ocurre en el Mac del usuario usando yt-dlp local con `--cookies-from-browser`, eliminando la dependencia de cookies en Modal Secret. El audio descargado se sube al servidor por `/process-file` para procesamiento GPU.
**Depends on**: Phase 6
**Success Criteria** (what must be TRUE):
  1. El usuario pega una URL de YouTube y la app descarga el audio localmente sin pedir cookies ni configuracion extra
  2. El audio descargado se sube automaticamente por `/process-file` y se procesa igual que un archivo arrastrado
  3. No se usa el endpoint `/process-url` ni el Modal Secret `youtube-cookies` para nuevas descargas
  4. El flujo muestra progreso: validando → descargando → subiendo → procesando → listo
  5. Si yt-dlp no esta instalado, la app muestra un mensaje claro con instrucciones de instalacion

Plans:
- [ ] TBD (run /gsd:plan-phase 8 to break down)

### Phase 9: Show chord finger position diagram alongside chord name
**Goal**: El usuario ve diagramas de posicion de dedos para guitarra junto a los nombres de acordes en ChordView, con datos generados en el pipeline del servidor y renderizados via Canvas en el cliente
**Requirements**: CHRD-01, CHRD-02, CHRD-03, CHRD-04, CHRD-05
**Depends on**: Phase 7
**Success Criteria** (what must be TRUE):
  1. Cada acorde detectado incluye datos de fingering (hasta 3 variaciones) en chords.json
  2. El diagrama muestra posiciones de dedos, cuerdas abiertas/silenciadas, cejilla y numero de traste
  3. Los diagramas se muestran para el acorde actual y el siguiente con jerarquia visual clara
  4. El toggle de visibilidad persiste globalmente y los diagramas estan activados por defecto
  5. La transposicion actualiza los diagramas al acorde transpuesto
**Plans:** 2/2 plans complete

Plans:
- [ ] 09-01-PLAN.md — Server: guitar.json bundle, fingerings.py lookup, chords.py extension con fingerings
- [ ] 09-02-PLAN.md — Client: ChordPosition model, ChordDiagramView Canvas, ChordView integration + toggle + layout
