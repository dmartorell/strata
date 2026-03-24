# Siyahamba

App de procesamiento de audio: importa una canción → separación de stems con Demucs → detección de acordes → reproducción interactiva con stems, letras sincronizadas y acordes.

- **Backend:** Python + FastAPI sobre Modal.com (serverless GPU T4)
- **Frontend:** macOS app nativa en SwiftUI (macOS 14+)

## Requisitos

- Python 3.11+
- [Modal CLI](https://modal.com/docs/guide) con cuenta configurada
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Estructura

```
server/           Backend (Modal + FastAPI)
  app.py          Definición de la app Modal (ProcessingService, AudioPipeline, web handler)
  auth/           Autenticación (JWT + bcrypt)
  pipeline/       Pipeline GPU (Demucs, acordes, alineación, packaging)
  processors/     Procesadores de audio
  usage/          Tracking de uso y costes
SiyahambaClient/  App macOS (SwiftUI)
  Auth/           Login + Keychain
  Import/         Importación de canciones
  Library/        Biblioteca local + cache
  Player/         Reproductor (stems, letras, acordes, waveforms)
  Network/        APIClient + endpoints
  Audio/          PlaybackEngine (AVAudioEngine multi-stem)
tests/            Tests de integración del backend
project.yml       Definición del proyecto Xcode (XcodeGen)
```

## Backend (Modal)

### Setup inicial

```bash
pip install modal
modal setup          # Autenticación con tu cuenta Modal
```

### Configurar secreto JWT (producción)

```bash
modal secret create siyahamba-secrets JWT_SECRET="tu-secreto-de-32-chars-minimo"
```

Sin esto, usa el secreto de desarrollo por defecto.

### Desplegar

```bash
cd server
modal deploy app.py
```

Esto despliega:
- **Web handler** (CPU, FastAPI) — endpoints REST
- **AudioPipeline** (GPU T4) — procesamiento de audio con Demucs
- **ProcessingService** (GPU T4) — servicio de procesamiento stub

La URL del deploy aparece en la salida: `https://<tu-usuario>--siyahamba-web.modal.run`

### Desarrollo local (hot reload)

```bash
cd server
modal serve app.py
```

### Tests

```bash
# Tests unitarios (sin Modal)
pytest tests/ -m "not integration"

# Tests de integración (requiere deploy previo)
pytest tests/ -m integration
```

### Dashboard de Modal

Monitorización de uso, logs, costes y contenedores:

**https://modal.com/apps**

Desde ahí puedes ver:
- Uso de GPU y costes en tiempo real
- Logs de cada función
- Cold starts y contenedores activos
- Historial de deploys

### Límites del free tier

- $30/mes de crédito gratuito
- Coste estimado por canción: ~$0.09 (GPU + overhead de contenedor)
- ~330 canciones/mes con el free tier
- Límite de gasto configurable en `server/usage/tracker.py` (`SPENDING_LIMIT_USD`)

## Frontend (macOS)

### Generar proyecto Xcode

```bash
xcodegen generate
```

Esto genera `SiyahambaClient.xcodeproj` a partir de `project.yml`.

### Build y run desde CLI

```bash
xcodebuild -project SiyahambaClient.xcodeproj \
  -scheme SiyahambaClient \
  -configuration Debug \
  build

# Build y ejecutar
xcodebuild -project SiyahambaClient.xcodeproj \
  -scheme SiyahambaClient \
  -configuration Debug \
  build && \
  open build/Debug/SiyahambaClient.app
```

### Abrir en Xcode

```bash
open SiyahambaClient.xcodeproj
```

Luego `Cmd+R` para build y ejecutar.

### Configuración

La app apunta por defecto a `https://dani-martorell--siyahamba-web.modal.run`. Para apuntar a otro backend:

```bash
# Variable de entorno (útil para desarrollo)
export SIYAHAMBA_API_URL="https://tu-url.modal.run"
```

O modificar `SiyahambaClient/Network/APIEndpoint.swift`.

## Usuarios

Usuarios definidos en `server/auth/users.json`. Para añadir uno nuevo:

```bash
# Generar hash bcrypt
python3 -c "import bcrypt; print(bcrypt.hashpw(b'tu-password', bcrypt.gensalt()).decode())"
```

Añadir al JSON y redesplegar (`modal deploy server/app.py`).
