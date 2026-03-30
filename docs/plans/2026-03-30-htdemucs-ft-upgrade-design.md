# Migración a htdemucs_ft para mejorar calidad de separación

**Fecha:** 2026-03-30
**Estado:** Aprobado

## Problema

Al mutear la voz, la calidad del audio instrumental es mediocre en la mayoría de canciones y muy mala (con distorsiones) en algunas. Es un problema generalizado, no específico de ciertos géneros. La causa raíz es el modelo `htdemucs` (base), que no separa limpiamente las fuentes y deja artefactos ("fantasmas" de voz en stems instrumentales).

## Solución

Cambiar el modelo de separación de `htdemucs` a `htdemucs_ft` (fine-tuned). Mejora de +1-2 dB SDR en todas las fuentes, perceptiblemente notable.

### Alternativas descartadas

- **Post-procesado de stems (filtros, normalización):** Mejora marginal (~5-10%). No puede recuperar información mal separada.
- **GPU más potente (A10G/A100):** Misma calidad, solo más rápido. x3 coste innecesario.

## Alcance

### Cambios en servidor

**`server/app.py`:**
- Cambiar `"htdemucs"` → `"htdemucs_ft"` en la carga del modelo.
- Validar parámetros de fallback OOM (`overlap=0.1, segment=7.5`) con canción larga.

**Sin cambios en:**
- `server/pipeline/separation.py` — `apply_model()` es agnóstico al modelo.
- `server/pipeline/` (resto) — misma estructura de output.
- Cliente macOS — mismo formato de stems (WAV 44100Hz stereo).

### Deployment

- `modal deploy` reconstruye imagen con pesos de `htdemucs_ft` (~330 MB extra).
- El cliente no necesita actualización. Las canciones nuevas se procesarán con el modelo mejorado automáticamente.
- Las canciones ya cacheadas mantienen la calidad antigua; para reprocesar, borrar de librería y reimportar.

## Impacto

| Métrica | Antes (htdemucs) | Después (htdemucs_ft) |
|---------|-------------------|------------------------|
| Tiempo/canción 4 min | ~45s | ~2-3 min |
| Coste/canción | ~€0.08 | ~€0.20-0.30 |
| Calidad (SDR) | Base | +1-2 dB |
| VRAM | ~1 GB | ~1.5 GB |
| Canciones/mes ($30 tier) | ~375 | ~100-150 |

## Riesgos

- **Cold start más lento:** ~10-20s extra por descarga de pesos mayores.
- **OOM en canciones largas:** Bajo riesgo (T4=16 GB VRAM), fallback existente con `segment` reducido.
