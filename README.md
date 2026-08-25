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
Siyahamba/        App macOS (SwiftUI)
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

Esto genera `Siyahamba.xcodeproj` a partir de `project.yml`.

### Build y run desde CLI

```bash
xcodebuild -project Siyahamba.xcodeproj \
  -scheme Siyahamba \
  -configuration Debug \
  build

# Build y ejecutar
xcodebuild -project Siyahamba.xcodeproj \
  -scheme Siyahamba \
  -configuration Debug \
  build && \
  open build/Debug/Siyahamba.app
```

### Abrir en Xcode

```bash
open Siyahamba.xcodeproj
```

Luego `Cmd+R` para build y ejecutar.

### Configuración

La app apunta por defecto a `https://dani-martorell--siyahamba-web.modal.run`. Para apuntar a otro backend:

```bash
# Variable de entorno (útil para desarrollo)
export SIYAHAMBA_API_URL="https://tu-url.modal.run"
```

O modificar `Siyahamba/Network/APIEndpoint.swift`.

## Importar desde YouTube

La Biblioteca incluye «Importar YouTube» para convertir localmente el audio de un único vídeo y enviarlo después al procesamiento habitual de stems. La conversión usa `yt-dlp`, Deno y `ffmpeg` empaquetados en la app, sin descargar herramientas durante el uso.

- Formatos: MP3 y M4A.
- Calidades: 128, 192 y 320 kbps. El valor inicial es MP3 a 192 kbps.
- Límites: vídeos de hasta 10 minutos y archivos convertidos de hasta 50 MB.
- URLs admitidas: `youtube.com/watch`, `youtu.be` y Shorts de YouTube. No se admiten playlists, vídeos privados, con inicio de sesión, restricción de edad, Premium o bloqueados por región.
- El título del vídeo pasa por la confirmación de metadatos. La URL de origen evita importar dos veces el mismo vídeo.

La conversión debe utilizarse únicamente con contenido propio o para el que se tengan los permisos necesarios. Si un vídeo no está disponible, importa un archivo de audio local.

### Actualizar herramientas para una release

Las versiones de `yt-dlp`, Deno, FFmpeg y LAME están fijadas con sus SHA-256 en `Tools/download-youtube-tools.sh` y documentadas en `ThirdParty/YouTubeTools/manifest.json`. Antes de una release:

1. Actualiza versión, URL, checksum y licencia en el script y el manifiesto.
2. Ejecuta `Tools/download-youtube-tools.sh` en macOS para regenerar los binarios arm64 y x86_64 dentro de `Siyahamba/Resources/YouTubeTools.bundle`.
3. Ejecuta `xcodegen generate`, build y tests.
4. Haz una conversión manual de un vídeo público menor de 10 minutos en Apple Silicon e Intel para MP3 192 kbps y M4A 192 kbps.

## Distribución y actualizaciones

La distribución usa firma `Developer ID Application`, notarización de Apple y [Sparkle](https://sparkle-project.org/). macOS valida la app sin el aviso de desarrollador no identificado y, desde la versión 1.5, las actualizaciones se instalan desde `Siyahamba → Buscar actualizaciones…`.

### Publicar una versión

Crear y subir un tag `vX.Y` ejecuta el workflow `.github/workflows/release.yml` en GitHub Actions. El workflow:

1. Compila y firma la app con Developer ID.
2. La envía a notarización y grapa el ticket de Apple.
3. Firma el ZIP con la clave EdDSA de Sparkle.
4. Publica el ZIP en [GitHub Releases](https://github.com/dmartorell/strata/releases) y el `appcast.xml` en GitHub Pages.

```bash
# Tras incrementar CFBundleVersion y CFBundleShortVersionString en project.yml
xcodegen generate
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug test
git commit -am "chore: bump version to X.Y"
git tag vX.Y
git push origin main --tags
```

La configuración inicial de certificados, API key de Apple y secretos de GitHub está en [`docs/release-process.md`](docs/release-process.md). Los usuarios de versiones anteriores a 1.5 deben instalar una vez el ZIP de la primera release con Sparkle. Después, las actualizaciones son in-app.

## Acceso

Contraseña compartida para todos los usuarios. La app solo pide la contraseña al abrir (sin username).

Para cambiar la contraseña:

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'nueva-password', bcrypt.gensalt()).decode())"
```

Actualizar el hash en `server/auth/users.json` y redesplegar (`modal deploy server/app.py`).
