# Guitar Tuner — Design

## Resumen

Afinador de guitarra integrado en el sidebar de stems del PlayerView. Captura audio del micrófono, detecta pitch mediante autocorrelación (vDSP), y muestra desviación visual respecto a la afinación estándar. Pausa la reproducción mientras está activo.

## Decisiones de diseño

- **Ubicación:** Sección colapsable al fondo del StemControlsView (debajo de las 4 pistas)
- **Afinación:** Solo estándar (E2, A2, D3, G3, B3, E4)
- **Detección:** Automática por defecto, con opción de fijar cuerda manualmente
- **Indicador:** Barra horizontal con indicador de desviación (rojo → amarillo → verde)
- **Pitch detection:** Autocorrelación con vDSP (Accelerate framework), sin dependencias externas
- **Requisito:** Reproducción pausada — no funciona simultáneamente con playback

## Arquitectura

### Componentes nuevos

```
TunerEngine (Audio/TunerEngine.swift)
  @Observable
  - AVAudioEngine independiente con tap en inputNode
  - Autocorrelación vDSP → frecuencia fundamental
  - Estado: detectedPitch, closestString, deviationCents, isActive, lockedString
  - start() / stop() con coordinación de PlaybackEngine

GuitarTuning (Audio/GuitarTuning.swift)
  - Enum GuitarString con 6 cuerdas estándar y frecuencias
  - closestString(to pitch:) → cuerda más cercana
  - deviationInCents(pitch:, target:) → desviación en cents

TunerView (Player/TunerView.swift)
  - Botón "Afinar" que expande/colapsa
  - Barra de desviación (Capsule, estilo sliders existentes)
  - Selector de cuerdas (6 botones tipo M/S) + toggle Auto
  - Valor numérico de cents
```

### Archivos a modificar

- `Player/StemControlsView.swift` — añadir TunerView debajo del Spacer
- `ContentView.swift` — instanciar TunerEngine y pasarlo por @Environment
- `Info.plist` — añadir NSMicrophoneUsageDescription
- Entitlements — añadir com.apple.security.device.audio-input

## Motor de audio

- AVAudioEngine independiente (no compartido con PlaybackEngine)
- Tap en inputNode: 44100Hz mono, buffers de 4096 samples (~93ms)
- Pipeline DSP: ventana Hanning (vDSP_vmul) → autocorrelación (vDSP_conv) → buscar primer pico → frecuencia
- Rango: 75Hz–350Hz (E2=82Hz a E4=330Hz con margen)
- Actualización: ~10Hz (suficiente para UI fluida)

## UI

### Estado colapsado
- Divider + botón con icono diapasón + "Afinar" (font 11, .secondary)

### Estado expandido (~120pt)
- Nota detectada + barra de desviación horizontal
- Valor numérico de cents
- 6 botones de cuerda (E2, A2, D3, G3, B3, E4) + botón Auto
- Botón Cerrar
- Colores: rojo (>20 cents) → amarillo (5-20) → verde (±5 cents)

## Integración con PlaybackEngine

- start(): pausa reproducción si activa, guarda wasPlaying
- stop(): restaura reproducción si wasPlaying
- TunerEngine recibe PlaybackEngine por init

## Edge cases

- Sin señal: barra centrada en gris, sin nota
- Ruido sin tono claro: umbral de confianza en autocorrelación
- Permiso denegado: texto "Micrófono no disponible" en el panel
- App cerrada con afinador activo: stop() en onDisappear
- Toggle rápido: debounce 0.3s antes de instalar/desinstalar tap

## Permisos

- `NSMicrophoneUsageDescription`: "Siyahamba necesita acceso al micrófono para el afinador de guitarra"
- Entitlement: `com.apple.security.device.audio-input`
