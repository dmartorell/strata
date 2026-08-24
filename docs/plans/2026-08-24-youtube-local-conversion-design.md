# Diseño: conversión local de vídeos de YouTube

## Objetivo

Sustituir el enlace externo roto `YT Convert` por una conversión local dentro de Siyahamba. El resultado se importa al flujo actual de procesamiento de canciones.

## Decisiones

- Conversión local con `yt-dlp` y `ffmpeg` empaquetados en la app.
- Sin servicio de conversión en Modal. El procesamiento posterior de stems mantiene su coste actual en Modal.
- Un solo vídeo por operación. Se admiten URLs `youtube.com/watch`, `youtu.be` y YouTube Shorts.
- Se excluyen playlists, vídeos privados, con inicio de sesión, edad restringida, Premium o bloqueados por región. La app sugiere importar un archivo local cuando corresponda.
- Formatos: MP3 y M4A.
- Calidades: 128, 192 y 320 kbps. Predeterminados: MP3 y 192 kbps.
- El título del vídeo se usa como nombre inicial y pasa por la confirmación de metadatos existente.
- Se almacena la URL de origen y se bloquean duplicados por URL, abriendo la canción ya existente.
- Se soportan Apple Silicon e Intel mediante binarios universales o binarios por arquitectura.
- Las versiones de `yt-dlp` se actualizan únicamente mediante releases de Siyahamba. El build verifica SHA-256 de los binarios y documenta sus licencias.

## Flujo de usuario

1. El botón `YT Convert` de Biblioteca abre `YouTubeConversionSheet` en lugar de abrir el navegador.
2. La hoja ofrece URL, formato, calidad y «Convertir e importar».
3. Se valida que sea un vídeo admitido y que dure como máximo 10 minutos.
4. `yt-dlp` descarga el audio localmente y `ffmpeg` genera el formato seleccionado.
5. La hoja muestra progreso global: descarga 0–80 % y conversión 80–100 %, con el estado correspondiente.
6. El archivo resultante se comprueba contra el límite de 50 MB.
7. Si es válido, entra en `MetadataConfirmationSheet`. El usuario puede modificar artista y título.
8. Al confirmar, `ImportViewModel` lo añade a la cola de importación existente.

## Arquitectura

- `YouTubeConversionSheet`: estado de formulario, progreso, cancelación, error y reintento.
- `YouTubeConverter`: servicio local que lanza y supervisa `yt-dlp` y `ffmpeg` mediante `Process`, fuera del actor principal.
- Recursos de aplicación: binarios firmados para cada arquitectura, localizados desde el bundle.
- `ImportViewModel`: conserva la responsabilidad de confirmar metadatos, encolar, subir y consultar el procesamiento remoto.
- La deduplicación por URL se añade al catálogo local, además de la deduplicación actual por hash de archivo.

## Errores y limpieza

- Se muestra un mensaje legible, un botón de reintento manual y «Ver detalles» para copiar el diagnóstico técnico.
- No hay reintento automático.
- «Cancelar» termina los procesos hijos y elimina el temporal.
- Al cerrar la app se cancela la conversión. En el siguiente arranque se eliminan restos temporales.
- El archivo temporal permanece hasta completar o cancelar la confirmación de metadatos, y se elimina después.

## Pruebas

- Pruebas unitarias con ejecutores simulados de `yt-dlp` y `ffmpeg` para validación, progreso, cancelación, errores y limpieza.
- Pruebas de integración locales sin acceso a YouTube real.
- Verificación manual con un vídeo público antes de cada release.
