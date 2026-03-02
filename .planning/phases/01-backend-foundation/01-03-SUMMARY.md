---
phase: 01-backend-foundation
plan: "03"
subsystem: infra
tags: [modal, demucs, whisperx, crema, ml-models, cold-start, gpu, image-baking]

requires:
  - "01-02: process_job Modal Function + stub pipeline desplegado"

provides:
  - "Modal image con pesos Demucs htdemucs + WhisperX base + CREMA chord model baked in"
  - "ProcessingService @app.cls con @modal.enter para pre-carga de modelos en arranque"
  - "image.run_function(download_models, gpu=T4) para baking de pesos en build time"

affects:
  - 02-gpu-pipeline (reemplazara stubs con modelos reales — ya cargados en self.*)
  - cold-start-budget (pesos en imagen, no descarga en runtime)

tech-stack:
  added:
    - torch + torchaudio (PyTorch con CUDA runtime incluido via pip)
    - demucs==4.0.1 (separacion de stems)
    - faster-whisper (WhisperX backend de transcripcion)
    - whisperx (transcripcion con timestamps)
    - crema==0.2.0 (reconocimiento de acordes)
    - apt: ffmpeg, libsndfile1 (dependencias sistema para audio)
  patterns:
    - "image.run_function(fn, gpu=T4): baking de pesos ML en imagen Modal en build time"
    - "@app.cls en lugar de @app.function para poder usar @modal.enter"
    - "@modal.enter preload_models(): carga modelos una vez por contenedor, no por request"
    - "modal.Cls.from_name('strata', 'ProcessingService')().process_job.spawn.aio() para spawn desde web handler"

key-files:
  created: []
  modified:
    - server/app.py
    - server/processors/stub_processor.py

key-decisions:
  - "Conversion de process_job function a ProcessingService class para poder usar @modal.enter"
  - "run_function(download_models, gpu=T4): GPU en build time para correcta inicializacion de CUDA"
  - "PyTorch via pip (no CUDA base image): ruta mas segura segun research, incluye CUDA runtime"
  - "stub_processor.py actualizado a modal.Cls.from_name pattern para spawn desde web handler"

requirements-completed: [INFR-03, INFR-04]

duration: ~15 min
completed: 2026-03-02
---

# Phase 01 Plan 03: ML Model Weights Baking Summary

**Modal image con pesos Demucs htdemucs + WhisperX base + CREMA chord model baked en build time, ProcessingService con @modal.enter para pre-carga de los tres modelos en arranque de contenedor**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-02T~07:30:00Z
- **Completed:** 2026-03-02 (pendiente verificacion cold start)
- **Tasks:** 1 de 1 completadas (checkpoint human-verify pendiente)
- **Files modified:** 2

## Accomplishments

- Imagen Modal actualizada con dependencias ML: torch, torchaudio, demucs==4.0.1, faster-whisper, whisperx, crema==0.2.0, ffmpeg, libsndfile1
- download_models() descarga pesos de Demucs htdemucs, WhisperX base y CREMA chord model durante la build de la imagen (run_function con gpu=T4)
- process_job convertido a ProcessingService @app.cls con @modal.enter que pre-carga los tres modelos en self.demucs_model, self.whisper_model, self.crema_model al arrancar cada contenedor
- stub_processor.py actualizado para usar modal.Cls.from_name("strata", "ProcessingService")().process_job.spawn.aio() en ambos endpoints de spawn

## Task Commits

1. **Task 1: Bake ML weights + @modal.enter preloading** - `0ee59fb` (feat)

## Files Created/Modified

- `server/app.py` - Imagen pesada con run_function, ProcessingService @app.cls, @modal.enter preload_models
- `server/processors/stub_processor.py` - Spawn actualizado a modal.Cls.from_name pattern

## Decisions Made

- Conversion de `@app.function process_job` a `@app.cls ProcessingService` para poder usar `@modal.enter`. Sin este patron, no hay lifecycle hook para pre-cargar modelos antes de la primera request.
- `run_function(download_models, gpu="T4")`: GPU en build time garantiza que CUDA se inicializa correctamente al descargar los pesos — los modelos PyTorch requieren GPU para su cache mas eficiente.
- PyTorch via pip (no imagen base CUDA): ruta mas segura, PyTorch bundlea su propio runtime CUDA, evita problemas de compatibilidad de versiones con imagenes base.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Actualizar spawn calls en stub_processor.py a modal.Cls.from_name**
- **Found during:** Task 1 (conversion de function a class)
- **Issue:** Al convertir process_job a ProcessingService.process_job, los spawn calls en stub_processor.py seguian usando modal.Function.from_name("strata", "process_job") que ya no existe
- **Fix:** Actualizar ambos endpoints (/process-file y /process-url) para usar modal.Cls.from_name("strata", "ProcessingService")().process_job
- **Files modified:** server/processors/stub_processor.py
- **Committed in:** 0ee59fb (parte del commit Task 1)

---

**Total deviations:** 1 auto-fixed (actualizacion necesaria de spawn calls por cambio de funcion a clase)
**Impact on plan:** Correccion tecnica obligatoria al convertir function a class. Sin cambio de alcance.

## Cold Start Measurement

**PENDIENTE — verificacion human-verify en curso.**

El usuario debe:
1. Hacer `modal deploy app.py` (primer deploy tardara varios minutos por descarga de pesos)
2. Esperar 2-3 minutos sin trafico para que el contenedor se apague
3. Medir: `time curl https://dani-martorell--strata-web.modal.run/health`
4. Gate: cold start debe ser <15 segundos

## Self-Check: PARTIAL

Verificacion pre-checkpoint:
- `server/app.py` actualizado con run_function, ProcessingService, @modal.enter: FOUND
- `server/processors/stub_processor.py` actualizado con modal.Cls.from_name: FOUND
- Commit 0ee59fb existe: FOUND
- Verificacion automatica plan: PASSED (heavy image definition ok)
- Cold start medido empiricamente: PENDIENTE (requiere deploy + medicion humana)

## Next Phase Readiness

- Phase 2 (GPU pipeline real) puede reemplazar stubs directamente en self.demucs_model, self.whisper_model, self.crema_model — los modelos ya estan pre-cargados
- CREMA 0.2.0 / Python 3.11 compatibilidad: se verificara durante el deploy de este plan
- Si CREMA falla en build, escalada requerida (no se elimina silenciosamente)

---
*Phase: 01-backend-foundation*
*Completed: 2026-03-02*
