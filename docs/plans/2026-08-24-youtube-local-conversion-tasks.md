# Task Tracker: conversión local de YouTube

> Tickets independientes para implementar el diseño de `2026-08-24-youtube-local-conversion-design.md`. Ejecutar en orden de dependencias. Cada ticket debe incluir sus pruebas y un commit propio.

## Mapa de archivos previsto

| Archivo | Responsabilidad |
|---|---|
| `project.yml` | Recursos ejecutables empaquetados y su pertenencia al target. |
| `Tools/download-youtube-tools.sh` | Descarga reproducible y verificada de binarios de build. |
| `ThirdParty/YouTubeTools/` | Manifiesto de versiones, SHA-256, licencias y binarios distribuidos. |
| `Siyahamba/Import/YouTubeConverter.swift` | Dominio de URL, metadatos, ejecución de procesos, progreso, límites y errores. |
| `Siyahamba/Import/YouTubeConversionSheet.swift` | Hoja de formato/calidad/URL, progreso, cancelación y reintento. |
| `Siyahamba/Import/ImportViewModel.swift` | Entrega del archivo convertido, persistencia de procedencia y deduplicación. |
| `Siyahamba/Library/LibraryStore.swift` | Búsqueda de canciones por URL de YouTube canónica. |
| `Siyahamba/Library/LibraryView.swift` | Sustitución del enlace externo por la hoja. |
| `Siyahamba/App/SiyahambaApp.swift` | Limpieza al arranque de conversiones abandonadas. |
| `SiyahambaTests/Import/YouTubeConverterTests.swift` | Pruebas del servicio con ejecutor simulado. |
| `SiyahambaTests/Import/YouTubeConversionSheetTests.swift` | Pruebas de estado de la hoja, si se extrae un modelo testeable. |
| `SiyahambaTests/Import/ImportViewModelTests.swift` | Handoff a metadatos, duplicados y limpieza. |

## Tickets

### [x] YT-01 — Empaquetar herramientas locales verificadas

> Completado el 2026-08-24. La build Debug pasa. `xcodebuild test` sigue bloqueado por dos tests obsoletos de `startURLImport`, que se reemplazarán en YT-03.

**Depende de:** —

**Objetivo:** Hacer disponibles `yt-dlp` y `ffmpeg` desde el bundle de Siyahamba, tanto en Apple Silicon como en Intel, sin descargar ejecutables durante el uso de la app.

**Alcance:**
- Crear `Tools/download-youtube-tools.sh` para descargar versiones fijadas de fuentes oficiales.
- Guardar en `ThirdParty/YouTubeTools/manifest.json` la versión, URL de origen, SHA-256, arquitectura y licencia de cada artefacto.
- El script debe comprobar SHA-256 antes de copiar el binario, marcarlo ejecutable y fallar con código distinto de cero si no coincide.
- Incluir binarios arm64 y x86_64, o un binario universal verificable, como recursos de `Siyahamba` en `project.yml`.
- Añadir una licencia de `yt-dlp` y la licencia exacta del build de FFmpeg distribuido. Seleccionar un build compatible con la distribución prevista.
- Añadir una función mínima y testeable de localización de recursos que seleccione la arquitectura correcta y devuelva un error español si falta o no es ejecutable.

**Fuera de alcance:** actualizar herramientas en caliente, descargar binarios al primer uso y ejecutar conversiones.

**Criterios de aceptación:**
- Una build Debug contiene ambos ejecutables dentro de `Siyahamba.app`.
- En un Mac arm64 se localiza arm64 y en Intel se localiza x86_64.
- El script falla si se altera un checksum.
- `xcodegen generate` y `xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug build` terminan correctamente.

**Pruebas:** prueba unitaria de selección de arquitectura usando rutas inyectadas, y prueba de shell que corrompa una copia temporal del artefacto para comprobar el rechazo.

---

### [x] YT-02 — Crear el conversor local con contrato testeable

> Completado el 2026-08-24. Build Debug correcta. La suite completa continúa bloqueada por los tests heredados de `startURLImport`, previstos para YT-03.

**Depende de:** YT-01

**Objetivo:** Implementar un servicio aislado que valide enlaces, consulte metadatos, descargue audio, lo convierta a MP3/M4A y comunique progreso y cancelación sin bloquear la UI.

**Alcance:**
- Crear `YouTubeConverter.swift` con tipos `YouTubeFormat` (`mp3`, `m4a`), `YouTubeQuality` (`128`, `192`, `320`), `YouTubeConversionRequest`, `YouTubeVideoMetadata`, `YouTubeConversionProgress` y errores localizados.
- Normalizar y validar URLs individuales de `youtube.com/watch`, `youtu.be` y Shorts. Rechazar playlists y hosts ajenos antes de lanzar procesos.
- Ejecutar un primer comando de `yt-dlp` para leer ID, título y duración. Rechazar duración superior a 600 segundos antes de descargar.
- Ejecutar descarga y conversión en un directorio único bajo `temporaryDirectory/SiyahambaYouTubeConversions/<UUID>/`.
- Traducir progreso de descarga a 0–80 % y de FFmpeg a 80–100 %, exponiendo también `descargando` y `convirtiendo`.
- Forzar salida sólo MP3/M4A y bitrate seleccionado. Sanitizar el título para que no forme rutas ni nombres inválidos.
- Comprobar que el resultado es menor o igual a 50 MB antes de devolverlo.
- Permitir cancelación: terminar ambos procesos hijos, esperar su salida y eliminar el directorio temporal.
- Definir un protocolo de ejecución de procesos para sustituir `Process` por un fake en pruebas. El servicio no debe ser `@MainActor`.

**Fuera de alcance:** UI, persistencia en biblioteca e importación al backend.

**Criterios de aceptación:**
- Una URL válida devuelve metadatos y un archivo temporal de extensión correcta.
- URL ajena, playlist, duración >10 min, salida >50 MB, proceso no encontrado, fallo de red y salida no cero producen errores distinguibles en español.
- Cancelar elimina el directorio temporal y no devuelve un archivo.
- Ninguna actualización observable de SwiftUI se hace desde un hilo no principal.

**Pruebas:** `YouTubeConverterTests.swift` con ejecutor simulado para cada comando y cada resultado anterior. No llamar a YouTube real en tests automatizados.

---

### [x] YT-03 — Gestionar temporales y procedencia de importaciones convertidas

> Completado el 2026-08-25. Build Debug correcta. La suite completa queda bloqueada por tests ajenos de `NetworkTests` que aún llaman a `APIClient.getUsage`.

**Depende de:** YT-02

**Objetivo:** Conectar un archivo convertido con la confirmación de metadatos existente sin borrarlo antes de que la cola lo consuma, y conservar la URL canónica de origen.

**Alcance:**
- Ampliar `PendingImportItem` para transportar la URL de origen de YouTube y una política/closure de limpieza del temporal, o introducir un tipo equivalente con esa única responsabilidad.
- Añadir a `ImportViewModel` una entrada explícita para un resultado de `YouTubeConverter`, que cree un único pendiente con el título obtenido del vídeo.
- Corregir la persistencia de procedencia en `runFileImport`: guardar `originalURL.absoluteString`, no `originalURL.path`, para no perder esquema ni host.
- Añadir `LibraryStore.song(forYouTubeURL:)` o una consulta equivalente basada en una URL canónica, y usarla antes de abrir la confirmación. Un duplicado no crea placeholder ni solicita subida.
- Asegurar limpieza del temporal al cancelar `MetadataConfirmationSheet`, al producirse un error de encolado, al finalizar la subida o al cancelar la importación.
- Mantener sin cambios el comportamiento de archivos seleccionados o arrastrados.
- Sustituir los tests obsoletos de `startURLImport` y `uploadURL` en `ImportViewModelTests.swift`/`MockAPIClient.swift`: esas APIs ya no existen y deben ser reemplazadas por casos del resultado local de `YouTubeConverter`.

**Fuera de alcance:** hoja de conversión y barra de progreso.

**Criterios de aceptación:**
- La confirmación recibe el título del vídeo y permite editar artista/título como cualquier archivo.
- Cancelar la confirmación borra el archivo convertido.
- Tras confirmar, el archivo sigue disponible hasta que `ImportViewModel` termina de leerlo.
- La entrada final de biblioteca conserva la URL completa de YouTube.
- Una URL equivalente (`youtu.be/<id>` frente a `youtube.com/watch?v=<id>`) no provoca una segunda importación.

**Pruebas:** ampliar `ImportViewModelTests.swift` con pendencia convertida, cancelación, conservación hasta upload, URL almacenada completa y duplicado por ID canónico.

---

### [x] YT-04 — Construir la hoja de conversión y su modelo de estado

> Completado el 2026-08-25. Build Debug correcta. La suite completa queda bloqueada por tests ajenos de `NetworkTests` que aún llaman a `APIClient.getUsage`.

**Depende de:** YT-02, YT-03

**Objetivo:** Ofrecer una hoja macOS completa para URL, formato, calidad, progreso, cancelación, error y reintento.

**Alcance:**
- Crear `YouTubeConversionSheet.swift` y un modelo `@Observable @MainActor` inyectable que dependa del protocolo de YT-02 y de `ImportViewModel`.
- Controles: campo URL, `Picker` de MP3/M4A, `Picker` de 128/192/320 kbps y botón «Convertir e importar».
- Valores iniciales: MP3 y 192 kbps.
- Durante conversión, deshabilitar URL y pickers. Mostrar `ProgressView(value:)` de 0 a 100, porcentaje accesible y etiqueta «Descargando» o «Convirtiendo».
- Mostrar «Cancelar» durante ejecución. Tras cancelación, restaurar el formulario conservando URL, formato y calidad.
- Ante error, mantener la hoja, enseñar mensaje español, permitir «Reintentar» y un botón «Ver detalles» que copie la salida diagnóstica al portapapeles.
- Al acabar, delegar el resultado en YT-03 y cerrar sólo esta hoja. La `MetadataConfirmationSheet` existente se presenta después mediante el estado global de `ContentView`.
- Si YT-03 encuentra duplicado, cerrar la hoja y ejecutar el callback que selecciona la canción existente en Biblioteca.

**Fuera de alcance:** cambiar `MetadataConfirmationSheet` salvo el soporte mínimo para el temporal definido en YT-03.

**Criterios de aceptación:**
- La hoja no se cierra mientras convierte.
- El progreso no retrocede entre fases.
- Cancelar no deja procesos ni temporales.
- Un error no borra los valores que el usuario introdujo.
- El éxito abre la confirmación de metadatos con los datos iniciales correctos.

**Pruebas:** extraer el estado fuera de la vista si hace falta y probar valores por defecto, activación/desactivación de controles, transición de progreso, cancelación, reintento y handoff usando un conversor fake.

---

### [ ] YT-05 — Integrar la conversión en Biblioteca y retirar y2mate

**Depende de:** YT-04

**Objetivo:** Reemplazar el botón externo actual por el flujo local, sin cambiar la importación por archivo ni la navegación de Biblioteca.

**Alcance:**
- En `LibraryView.swift`, sustituir `NSWorkspace.shared.open("https://v1.y2mate.nu/")` por estado de presentación de `YouTubeConversionSheet`.
- Cambiar ayuda y etiquetas para que describan importación desde YouTube, no conversión web externa.
- Pasar `ImportViewModel`, `LibraryStore` y el callback `onSongSelected` necesarios respetando los `@Environment` existentes.
- Eliminar el uso de AppKit que sólo existía para abrir la URL si ya no se necesita en ese archivo.
- Comprobar que la hoja de metadatos global de `ContentView` sigue siendo la única presentación de confirmación.

**Fuera de alcance:** rediseñar la Biblioteca o los controles de importación de archivo.

**Criterios de aceptación:**
- Pulsar `YT Convert` no abre navegador.
- El botón abre la hoja local con los valores definidos.
- La importación normal por selector y drag-and-drop no cambia.
- El build no contiene referencias a `y2mate`.

**Pruebas:** test de UI/manual del botón y búsqueda `rg -n "y2mate" Siyahamba` sin resultados.

---

### [ ] YT-06 — Limpieza al arranque, endurecimiento y verificación de release

**Depende de:** YT-01, YT-03, YT-05

**Objetivo:** Cerrar los casos de interrupción y verificar el flujo distribuible en un Mac real sin incorporar dependencia de red en la suite automatizada.

**Alcance:**
- Añadir a `YouTubeConverter` o a un `YouTubeConversionTemporaryStore` la limpieza de `temporaryDirectory/SiyahambaYouTubeConversions/`.
- Lanzar esa limpieza de forma asíncrona al iniciar la app autenticada desde `SiyahambaApp.swift`; no bloquear la carga de Biblioteca.
- Garantizar que no se registran URLs completas ni argumentos de procesos que puedan contener información sensible en logs de producción.
- Documentar en el README el flujo local, los formatos/calidades, límites de 10 minutos/50 MB, restricciones soportadas, uso responsable y cómo actualizar binarios al preparar una release.
- Ejecutar build y tests. Hacer smoke test manual en Apple Silicon e Intel con un vídeo público menor de 10 minutos para MP3 192 y M4A 192.
- Verificar manualmente cancelación durante descarga y conversión, error de URL no admitida, vídeo >10 min, metadatos editables, duplicado por URL y limpieza tras cerrar/reabrir la app.

**Fuera de alcance:** retries automáticos, playlists, cuentas/cookies de YouTube y actualización independiente de herramientas.

**Criterios de aceptación:**
- Los temporales de una conversión abandonada se eliminan en el siguiente arranque.
- El README describe límites y mantenimiento real.
- `xcodegen generate`, build y tests pasan.
- Las dos arquitecturas han superado el smoke test manual documentado.

**Pruebas:** añadir prueba de limpieza con directorio temporal aislado. Registrar los resultados manuales de release en el PR o en el changelog de la versión.

## Orden recomendado

1. YT-01
2. YT-02
3. YT-03
4. YT-04
5. YT-05
6. YT-06

## Cobertura del diseño

| Requisito | Ticket |
|---|---|
| Conversión local sin coste de conversión en backend | YT-01, YT-02 |
| MP3/M4A y 128/192/320, MP3 192 predeterminado | YT-02, YT-04 |
| Vídeos individuales, watch/youtu.be/Shorts | YT-02 |
| Máximo 10 min y 50 MB | YT-02 |
| Progreso, cancelación y reintento manual | YT-02, YT-04 |
| Confirmación de metadatos e importación actual | YT-03, YT-04 |
| Procedencia y deduplicación por URL | YT-03 |
| Limpieza ante cancelación/cierre/reinicio | YT-02, YT-03, YT-06 |
| Binarios verificados y multi-arquitectura | YT-01 |
| Errores comprensibles y detalle copiable | YT-02, YT-04 |
| Pruebas sin YouTube real y smoke test manual | YT-02 a YT-06 |
