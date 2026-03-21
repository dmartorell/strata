# Siyahamba — Planning de Desarrollo

## Resumen del proyecto

App nativa macOS (SwiftUI) para separación de pistas, pitch shifting en tiempo real, letras sincronizadas y detección de acordes. El usuario puede importar canciones arrastrando un archivo de audio o pegando una URL de YouTube. El procesamiento pesado se externaliza a Modal (serverless GPU). El cliente es ligero (<100 MB). Incluye autenticación simple y control de gasto.

---

## Arquitectura

```
┌──────── Cliente macOS (SwiftUI) ──────────────────┐
│                                                    │
│  Login (solo primera vez, sesión persistente)      │
│                                                    │
│  Entrada dual:                                     │
│  - Drag & drop archivo (.mp3/.wav/.flac/.m4a)     │
│  - Pegar URL de YouTube                            │
│                                                    │
│  Reproducción:                                     │
│  - Multi-stem player (AVAudioEngine)              │
│  - Pitch shifting (AVAudioUnitTimePitch)           │
│  - Overlay letras + acordes sincronizados          │
│  - Biblioteca local (caché de canciones)           │
│                                                    │
│  Menú: Siyahamba → Uso este mes                   │
│  (canciones procesadas + coste estimado)           │
└──────────────┬────────────────────────────────────┘
               │ HTTPS
               │ POST /login         (solo primera vez)
               │ POST /process-file  (sube audio)
               │ POST /process-url   (envía URL)
               │ GET  /usage         (gasto del mes)
┌──────────────▼────────────────────────────────────┐
│         Modal (Serverless GPU - T4)                │
│         Spending limit: $10/mes                    │
│         Concurrency limit: 2 GPUs máx.             │
│                                                    │
│  ┌─ Auth ───────────────────────────────────┐     │
│  │ users.json (bcrypt) → JWT (90 días)      │     │
│  │ Todos los endpoints validan JWT          │     │
│  └──────────────────────────────────────────┘     │
│                                                    │
│  ┌─ Ingesta ────────────────────────────────┐     │
│  │ Si URL → yt-dlp descarga audio (~5s)     │     │
│  │ Si archivo → recibe bytes directamente    │     │
│  └──────────────┬───────────────────────────┘     │
│                 ▼                                   │
│  ┌─ Pipeline de procesamiento ──────────────┐     │
│  │ 1. Demucs v4 → 4 stems                   │     │
│  │ 2. WhisperX (sobre stem vocal) → letras   │     │
│  │ 3. CREMA (sobre stem other) → acordes     │     │
│  └──────────────┬───────────────────────────┘     │
│                 ▼                                   │
│  ┌─ Tracking de uso ───────────────────────┐      │
│  │ usage.json: canciones + segundos GPU     │      │
│  │ GET /usage → resumen del mes actual      │      │
│  └──────────────────────────────────────────┘     │
│                                                    │
│  Respuesta: ZIP con stems + lyrics.json +          │
│             chords.json + metadata.json             │
└───────────────────────────────────────────────────┘
```

### Flujos de usuario

**Primera vez (único momento con fricción):**

1. Abre la app
2. Escribe la contraseña que le dieron → pulsa "Entrar"
3. No vuelve a ver esta pantalla en 90 días

**Uso diario — Flujo A (archivo local):**

1. Abre la app → va directo a la biblioteca
2. Arrastra archivo de audio a la app
3. Espera ~1 minuto → reproducción interactiva

**Uso diario — Flujo B (YouTube):**

1. Abre la app → va directo a la biblioteca
2. Pega URL de YouTube
3. Espera ~1 minuto → reproducción interactiva

**Consultar gasto:**

1. Menú superior: Siyahamba → Uso este mes
2. Ve: "12 canciones procesadas · Coste estimado: $0.35"

**En ambos flujos:** Si la canción ya fue procesada → carga instantánea desde caché local.

---

## Stack tecnológico

### Servidor (Python)

| Componente | Tecnología | Función |
|---|---|---|
| Infra | Modal (serverless, GPU T4) | Hosting y ejecución |
| Auth | bcrypt + PyJWT | Login simple, tokens de 90 días |
| Descarga YouTube | yt-dlp | Extracción de audio desde URL |
| Separación | Demucs v4 (HTDemucs) | 4 stems: vocals, drums, bass, other |
| Letras | WhisperX | Transcripción con timestamps word-level |
| Acordes | CREMA / madmom | Detección de acordes con timestamps |
| Tracking | usage.json (Modal Volume) | Registro de uso por mes |

### Cliente (Swift)

| Componente | Tecnología | Función |
|---|---|---|
| UI | SwiftUI | Interfaz nativa macOS |
| Audio engine | AVAudioEngine | Reproducción multi-stem |
| Pitch shift | AVAudioUnitTimePitch | Cambio de tono en tiempo real |
| Networking | URLSession | Comunicación con Modal |
| Auth local | Keychain Services | Almacenamiento seguro del token JWT |
| Persistencia | FileManager + JSON | Biblioteca local de canciones |

---

## Estructura del proyecto

```
siyahamba/
├── server/
│   ├── app.py                  # Entrypoint Modal + endpoints
│   ├── auth/
│   │   ├── users.json          # Credenciales (username + bcrypt hash)
│   │   └── auth.py             # Login + validación JWT
│   ├── processors/
│   │   ├── youtube_dl.py       # Descarga audio desde YouTube (yt-dlp)
│   │   ├── demucs_proc.py      # Separación de stems
│   │   ├── whisper_proc.py     # Transcripción de letras
│   │   └── chord_proc.py       # Detección de acordes
│   ├── usage/
│   │   └── tracker.py          # Registro y consulta de uso mensual
│   └── requirements.txt
│
└── Siyahamba/                 # Proyecto Xcode
    ├── App/
    │   └── SiyahambaApp.swift    # Entry point
    ├── Models/
    │   ├── Song.swift          # Modelo de canción (soporta ambos orígenes)
    │   ├── SongSource.swift    # Enum: .file(path) | .youtube(url, title, thumbnail)
    │   ├── LyricsData.swift    # Modelo de letras timestamped
    │   ├── ChordData.swift     # Modelo de acordes timestamped
    │   └── UsageData.swift     # Modelo de gasto mensual
    ├── Views/
    │   ├── LoginView.swift     # Pantalla de login (solo contraseña)
    │   ├── MainView.swift      # Biblioteca + zona de entrada dual
    │   ├── ImportView.swift    # Drop zone + campo URL + estado de proceso
    │   ├── PlayerView.swift    # Vista principal del reproductor
    │   ├── StemMixerView.swift # Controles de volumen/mute por stem
    │   ├── PitchControl.swift  # Slider de pitch
    │   ├── TimelineView.swift  # Barra de progreso
    │   ├── LyricsView.swift    # Letras sincronizadas
    │   ├── ChordsView.swift    # Acordes sincronizados
    │   └── UsageView.swift     # Ventana de gasto mensual
    ├── Audio/
    │   ├── AudioEngine.swift   # AVAudioEngine multi-stem
    │   └── PitchShifter.swift  # AVAudioUnitTimePitch wrapper
    ├── Services/
    │   ├── APIClient.swift     # Comunicación con Modal (todos los endpoints)
    │   ├── AuthService.swift   # Login + gestión de token en Keychain
    │   └── SongLibrary.swift   # Gestión de biblioteca local + caché
    └── Resources/
        └── Assets.xcassets
```

---

## Autenticación

### Diseño simplificado para usuario no técnico

- **Sin campo de usuario visible:** Si hay pocos usuarios, el username puede ir implícito o prefijado. El usuario solo escribe su contraseña.
- **Sesión de 90 días:** Token JWT con expiración larga. Almacenado en Keychain (persiste entre reinicios).
- **Textos grandes, botón amplio, mensajes claros:** "Contraseña incorrecta" en vez de códigos de error.
- **Renovación silenciosa:** Si el token está próximo a expirar, se renueva automáticamente sin molestar al usuario.

### users.json (servidor)

```json
[
  {
    "username": "papa",
    "password_hash": "$2b$12$..."
  },
  {
    "username": "hijo",
    "password_hash": "$2b$12$..."
  }
]
```

Añadir usuario = añadir línea al JSON + redesplegar (`modal deploy app.py`).

### Flujo técnico

```
Cliente                          Servidor
  │                                │
  │  POST /login                   │
  │  { password: "xxx" }           │
  │  ─────────────────────────►    │
  │                                │  Valida bcrypt
  │  { token: "eyJhbG..." }       │
  │  ◄─────────────────────────    │
  │                                │
  │  Guarda token en Keychain      │
  │                                │
  │  POST /process-url             │
  │  Authorization: Bearer eyJ...  │
  │  ─────────────────────────►    │
  │                                │  Valida JWT
  │                                │  Procesa canción
  │  ZIP con resultados            │
  │  ◄─────────────────────────    │
```

---

## Tracking de uso y gasto

### Servidor: usage.json (almacenado en Modal Volume)

```json
{
  "2025-03": {
    "songs_processed": 12,
    "gpu_seconds": 540,
    "estimated_cost_usd": 0.35,
    "by_user": {
      "papa": { "songs": 8, "gpu_seconds": 360 },
      "hijo": { "songs": 4, "gpu_seconds": 180 }
    }
  }
}
```

Cada procesamiento registra: usuario, duración GPU, timestamp. El coste se estima con la tarifa de Modal (~$0.000164/s para T4).

### GET /usage

```
Request:
  Authorization: Bearer eyJ...

Response:
  {
    "month": "2025-03",
    "songs_processed": 12,
    "gpu_seconds": 540,
    "estimated_cost_usd": 0.35
  }
```

### Cliente: menú "Uso este mes"

Accesible desde la barra de menú de macOS: **Siyahamba → Uso este mes**

Muestra una ventana simple:

```
┌─────────────────────────────────┐
│  Uso este mes (marzo 2025)      │
│                                 │
│  🎵 12 canciones procesadas     │
│  💰 Coste estimado: $0.35      │
│                                 │
│  Límite mensual: $10.00         │
│  ━━━━━━░░░░░░░░░░░░░░░  3.5%   │
│                                 │
│              [ Cerrar ]         │
└─────────────────────────────────┘
```

---

## Formatos de datos

### metadata.json

```json
{
  "id": "a1b2c3d4",
  "title": "Hotel California",
  "artist": "Eagles",
  "duration": 391.2,
  "source": {
    "type": "youtube",
    "url": "https://www.youtube.com/watch?v=...",
    "thumbnail": "https://i.ytimg.com/vi/.../maxresdefault.jpg"
  },
  "processed_at": "2025-03-01T14:30:00Z"
}
```

Para archivos locales:

```json
{
  "type": "file",
  "filename": "hotel_california.mp3"
}
```

### lyrics.json

```json
{
  "language": "en",
  "segments": [
    {
      "start": 12.4,
      "end": 15.1,
      "text": "Yesterday all my troubles seemed so far away",
      "words": [
        { "word": "Yesterday", "start": 12.4, "end": 12.9 },
        { "word": "all", "start": 13.0, "end": 13.2 },
        { "word": "my", "start": 13.2, "end": 13.4 }
      ]
    }
  ]
}
```

### chords.json

```json
{
  "chords": [
    { "start": 0.0, "end": 2.1, "chord": "Am" },
    { "start": 2.1, "end": 4.3, "chord": "F" },
    { "start": 4.3, "end": 6.5, "chord": "C" },
    { "start": 6.5, "end": 8.7, "chord": "G" }
  ]
}
```

### Estructura de caché local

```
~/Music/Siyahamba/
├── a1b2c3d4/                   # ID único por canción
│   ├── metadata.json
│   ├── vocals.wav
│   ├── drums.wav
│   ├── bass.wav
│   ├── other.wav
│   ├── lyrics.json
│   └── chords.json
├── e5f6g7h8/
│   ├── ...
└── library.json                # Índice de toda la biblioteca
```

---

## API del servidor

### POST /login

```
Request:
  Content-Type: application/json
  Body: { "password": "xxx" }
  (o { "username": "papa", "password": "xxx" } si hay múltiples usuarios)

Response 200:
  { "token": "eyJhbG...", "expires_in": 7776000 }

Response 401:
  { "error": "Contraseña incorrecta" }
```

### POST /process-file

```
Request:
  Authorization: Bearer eyJ...
  Content-Type: multipart/form-data
  Body: audio_file (binary)

Response 200:
  Content-Type: application/zip
  Body: ZIP con stems + lyrics.json + chords.json + metadata.json
```

### POST /process-url

```
Request:
  Authorization: Bearer eyJ...
  Content-Type: application/json
  Body: { "url": "https://www.youtube.com/watch?v=..." }

Response 200:
  Content-Type: application/zip
  Body: ZIP con stems + lyrics.json + chords.json + metadata.json
```

### GET /usage

```
Request:
  Authorization: Bearer eyJ...

Response 200:
  {
    "month": "2025-03",
    "songs_processed": 12,
    "gpu_seconds": 540,
    "estimated_cost_usd": 0.35,
    "spending_limit_usd": 10.00
  }
```

### Códigos de error

| Código | Significado |
|---|---|
| 200 | Operación exitosa |
| 400 | URL inválida o formato de audio no soportado |
| 401 | Token inválido o expirado → app muestra login |
| 413 | Archivo demasiado grande (límite: 50 MB) |
| 422 | yt-dlp no pudo descargar (vídeo privado, eliminado, etc.) |
| 429 | Spending limit alcanzado este mes |
| 500 | Error interno de procesamiento |
| 504 | Timeout (canción demasiado larga, >10 min) |

---

## Fases de desarrollo

### Fase 1 — Servidor Modal (5-6 días)

**Objetivo:** Servidor completo con auth, procesamiento y tracking de uso.

| Tarea | Detalle | Tiempo |
|---|---|---|
| 1.1 | Setup cuenta Modal + proyecto base + imagen Docker | 0.5 día |
| 1.2 | Auth: users.json + endpoint /login + middleware JWT | 1 día |
| 1.3 | Integrar yt-dlp — descarga audio desde URL de YouTube | 0.5 día |
| 1.4 | Integrar Demucs v4 — separación en 4 stems | 1 día |
| 1.5 | Integrar WhisperX — letras con timestamps sobre stem vocal | 1 día |
| 1.6 | Integrar CREMA — acordes con timestamps | 1 día |
| 1.7 | Endpoints /process-file y /process-url (con auth) | 0.5 día |
| 1.8 | Tracking de uso: usage.json + endpoint GET /usage | 0.5 día |
| 1.9 | Spending limit en Modal dashboard + concurrency_limit=2 | 0.5 hora |
| 1.10 | Manejo de errores + validación de inputs | 0.5 día |

**Entregable:** `modal deploy app.py` funcionando. Test con curl para todos los endpoints.

**Validación:**
- [ ] POST /login con contraseña correcta → token JWT
- [ ] POST /login con contraseña incorrecta → 401
- [ ] Endpoints /process-* sin token → 401
- [ ] POST /process-file con MP3 → ZIP con 4 stems + JSONs
- [ ] POST /process-url con URL de YouTube → mismo resultado + metadata
- [ ] Error 422 si URL no válida o vídeo no existe
- [ ] GET /usage → resumen del mes con canciones y coste
- [ ] Concurrency limit: máximo 2 procesamientos simultáneos
- [ ] Spending limit configurado en Modal dashboard
- [ ] Tiempo de proceso: <60s (archivo) / <65s (URL)

---

### Fase 2 — Audio Engine (3-4 días)

**Objetivo:** Reproductor multi-stem con pitch shifting funcionando en vista mínima.

| Tarea | Detalle | Tiempo |
|---|---|---|
| 2.1 | Proyecto Xcode + estructura base | 0.5 día |
| 2.2 | AVAudioEngine con 4 PlayerNodes (uno por stem) | 1 día |
| 2.3 | Mixer con volumen independiente por stem | 0.5 día |
| 2.4 | AVAudioUnitTimePitch global para pitch shifting | 0.5 día |
| 2.5 | Controles play/pause/seek | 1 día |

**Entregable:** Vista mínima que reproduce 4 stems sincronizados con control de volumen y pitch.

**Validación:**
- [ ] 4 stems suenan sincronizados
- [ ] Mute/solo por stem funciona
- [ ] Pitch shift sin cortes ni recargas
- [ ] Seek a cualquier punto de la canción

---

### Fase 3 — Login + Integración API + Biblioteca (3-4 días)

**Objetivo:** Login funcional, entrada dual conectada al servidor, biblioteca con caché.

| Tarea | Detalle | Tiempo |
|---|---|---|
| 3.1 | LoginView: campo de contraseña + botón "Entrar" (textos grandes) | 0.5 día |
| 3.2 | AuthService: login + almacenamiento JWT en Keychain + renovación | 0.5 día |
| 3.3 | ImportView: drop zone para archivos + campo de texto para URL | 0.5 día |
| 3.4 | Validación de entrada: archivo válido o URL de YouTube | 0.5 día |
| 3.5 | APIClient: /process-file y /process-url (con JWT) | 0.5 día |
| 3.6 | Descarga y descompresión de ZIP resultado | 0.5 día |
| 3.7 | SongLibrary: caché en ~/Music/Siyahamba/ + library.json | 0.5 día |
| 3.8 | Estados de UI: validando → procesando → listo / error | 0.5 día |

**Entregable:** Login → entrada dual → procesamiento → reproducción. Caché operativa.

**Validación:**
- [ ] Login con contraseña correcta → accede a la app
- [ ] Contraseña incorrecta → mensaje claro "Contraseña incorrecta"
- [ ] Cerrar y reabrir app → no pide login (token en Keychain)
- [ ] Token expirado → muestra login de nuevo
- [ ] Drag & drop de MP3/WAV/FLAC/M4A → procesa correctamente
- [ ] Pegar URL de YouTube → procesa correctamente
- [ ] URL inválida → mensaje de error claro
- [ ] Canciones procesadas cargan desde caché
- [ ] Metadata de YouTube visible en biblioteca

---

### Fase 4 — Letras sincronizadas (2-3 días)

**Objetivo:** Overlay de letras que sigue la reproducción en tiempo real.

| Tarea | Detalle | Tiempo |
|---|---|---|
| 4.1 | Parsear lyrics.json y modelo LyricsData | 0.5 día |
| 4.2 | LyricsView: mostrar línea actual + contexto | 1 día |
| 4.3 | Sincronización con posición de reproducción | 0.5 día |
| 4.4 | Highlight palabra actual (estilo karaoke) | 0.5 día |

**Entregable:** Letras que avanzan en tiempo real, estilo karaoke.

**Validación:**
- [ ] Letras sincronizadas con el audio (±200ms tolerancia)
- [ ] Highlight de palabra actual
- [ ] Se actualiza correctamente al hacer seek
- [ ] Funciona con pitch shift activo

---

### Fase 5 — Acordes sincronizados (2 días)

**Objetivo:** Overlay de acordes que sigue la reproducción en tiempo real.

| Tarea | Detalle | Tiempo |
|---|---|---|
| 5.1 | Parsear chords.json y modelo ChordData | 0.5 día |
| 5.2 | ChordsView: mostrar acorde actual + próximo | 1 día |
| 5.3 | Sincronización con posición de reproducción | 0.5 día |

**Entregable:** Acordes visibles en tiempo real junto a las letras.

**Validación:**
- [ ] Acorde actual visible y destacado
- [ ] Transiciones suaves entre acordes
- [ ] Se actualiza correctamente al hacer seek

---

### Fase 6 — UI final, uso mensual y pulido (3-4 días)

**Objetivo:** Interfaz completa con panel de gasto y pulido visual.

| Tarea | Detalle | Tiempo |
|---|---|---|
| 6.1 | MainView: biblioteca con thumbnails + drop zone + campo URL | 1 día |
| 6.2 | PlayerView: layout completo con todos los componentes | 0.5 día |
| 6.3 | UsageView: ventana "Uso este mes" (menú Siyahamba → Uso este mes) | 0.5 día |
| 6.4 | Waveform visual por stem | 0.5 día |
| 6.5 | Atajos de teclado (espacio=play, flechas=seek, ⌘V=pegar URL) | 0.5 día |
| 6.6 | Pulido visual, dark mode, iconos, textos accesibles | 0.5 día |

**Entregable:** App lista para uso diario.

**Validación:**
- [ ] Menú Siyahamba → Uso este mes muestra canciones y coste
- [ ] Barra de progreso visual del spending limit
- [ ] Entrada dual intuitiva
- [ ] Navegación fluida entre biblioteca y reproductor
- [ ] Thumbnails de YouTube visibles en biblioteca
- [ ] Atajos de teclado funcionando
- [ ] Aspecto visual profesional y accesible

---

## Estimación total

| Fase | Tiempo |
|---|---|
| Fase 1 — Servidor (auth + procesamiento + tracking) | 5-6 días |
| Fase 2 — Audio Engine | 3-4 días |
| Fase 3 — Login + API + Biblioteca | 3-4 días |
| Fase 4 — Letras | 2-3 días |
| Fase 5 — Acordes | 2 días |
| Fase 6 — UI + Uso mensual + Pulido | 3-4 días |
| **Total** | **~3-4 semanas** |

---

## Coste estimado

| Concepto | Coste |
|---|---|
| Modal (GPU) | $0/mes (tier gratuito cubre ~100 canciones/mes) |
| Modelos IA | $0 (open source: Demucs, WhisperX, CREMA) |
| yt-dlp | $0 (open source) |
| Apple Developer ID | $0 (opcional, $99/año solo si quieres firmar la app) |
| **Total mensual** | **$0** |

---

## Protecciones del servidor

| Medida | Configuración |
|---|---|
| Autenticación | JWT con expiración 90 días. Solo usuarios en users.json |
| Spending limit | $10/mes en Modal dashboard. Si se alcanza → error 429 |
| Concurrency limit | Máximo 2 GPUs simultáneas (`concurrency_limit=2`) |

---

## Requisitos mínimos

- **Desarrollo:** Mac con Xcode 15+, cuenta Modal gratuita, Python 3.11+
- **Ejecución cliente:** macOS 14+ (Sonoma), cualquier Mac
- **Ejecución servidor:** Gestionado por Modal (GPU T4)

---

## Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| yt-dlp deja de funcionar con YouTube | Alto | yt-dlp se actualiza frecuentemente. Actualizar en imagen Modal. Fallback: entrada por archivo |
| Precisión de acordes (~80-85%) | Medio | Aceptar como limitación. Opción futura: edición manual |
| Cold start de Modal (~15s) | Bajo | Mostrar "Iniciando servidor..." en UI |
| Canciones con mucha reverb | Bajo | Demucs maneja bien la mayoría. Artefactos menores en casos extremos |
| Modal cambia pricing | Bajo | Alternativas: Replicate, RunPod, o migrar a local |
| Vídeos con restricciones regionales | Bajo | Error claro. Usuario puede usar drag & drop como alternativa |
| Token JWT expirado | Bajo | App detecta 401 y muestra login. Experiencia fluida |