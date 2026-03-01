# Strata

## What This Is

App nativa macOS (SwiftUI) para separación de pistas de audio, pitch shifting en tiempo real, letras sincronizadas estilo karaoke y detección de acordes. El usuario importa canciones arrastrando archivos de audio o pegando URLs de YouTube. El procesamiento pesado (Demucs, WhisperX, CREMA) corre en Modal (serverless GPU). El cliente es ligero y con aspecto nativo macOS.

## Core Value

El flujo completo debe funcionar sin fricciones: importar una canción (archivo o YouTube) → esperar ~1 minuto → reproducción interactiva con stems separados, letras y acordes.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Autenticación simple con contraseña, sesión persistente 90 días (JWT + Keychain)
- [ ] Importar audio por drag & drop (MP3/WAV/FLAC/M4A)
- [ ] Importar audio pegando URL de YouTube (yt-dlp en servidor)
- [ ] Separación en 4 stems con Demucs v4 (vocals, drums, bass, other)
- [ ] Reproducción multi-stem sincronizada (AVAudioEngine)
- [ ] Control de volumen/mute independiente por stem
- [ ] Pitch shifting en tiempo real (AVAudioUnitTimePitch)
- [ ] Letras sincronizadas palabra a palabra estilo karaoke (WhisperX)
- [ ] Detección y visualización de acordes sincronizados (CREMA)
- [ ] Biblioteca local con caché de canciones procesadas (~Music/Strata/)
- [ ] Tracking de uso mensual (canciones + coste GPU estimado)
- [ ] Panel "Uso este mes" accesible desde menú de la app

### Out of Scope

- Chat en tiempo real — no es relevante para el caso de uso
- Vídeo — solo audio, sin reproducción de vídeo
- App móvil (iOS/Android) — macOS only por ahora
- OAuth / login social — contraseña directa es suficiente para 2 usuarios
- Edición manual de letras/acordes — aceptar output de los modelos tal cual
- Distribución en App Store — uso personal, sin firmar

## Context

- **Usuarios:** 2 personas (padre e hijo), uso personal para practicar instrumentos y cantar
- **Fuentes de audio:** mitad archivos locales, mitad YouTube
- **Macs destino:** Apple Silicon (M1) y posiblemente Intel, ambos con macOS 14+ (Sonoma)
- **Estética:** aspecto nativo macOS, limpia y funcional
- **Servidor:** Modal con GPU T4, tier gratuito cubre ~100 canciones/mes
- **Modelos IA:** todos open source y gratuitos (Demucs v4, WhisperX, CREMA/madmom)
- **Caché local:** canciones ya procesadas cargan instantáneamente sin servidor

## Constraints

- **Infra servidor**: Modal serverless GPU (T4) — spending limit $10/mes, max 2 GPUs simultáneas
- **Tamaño cliente**: <100 MB, ligero
- **Compatibilidad**: macOS 14+ (Sonoma), soporte Apple Silicon + Intel
- **Tiempo de proceso**: <60s archivo local, <65s URL de YouTube
- **Tamaño máximo archivo**: 50 MB
- **Duración máxima canción**: 10 minutos

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Modal como backend serverless | GPU bajo demanda sin mantener servidor, tier gratuito generoso | — Pending |
| Demucs v4 para separación | Estado del arte en separación de stems, open source | — Pending |
| WhisperX para letras | Transcripción word-level con timestamps precisos, open source | — Pending |
| CREMA para acordes | Detección de acordes con timestamps, ~80-85% precisión aceptable | — Pending |
| JWT 90 días + Keychain | Mínima fricción para 2 usuarios, login solo una vez cada 3 meses | — Pending |
| Caché en ~/Music/Strata/ | Localización estándar macOS para archivos de música | — Pending |
| Aspecto nativo macOS (SwiftUI) | Coherente con el sistema, familiar para los usuarios | — Pending |

---
*Last updated: 2026-03-02 after initialization*
