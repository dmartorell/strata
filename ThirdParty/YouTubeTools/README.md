# Herramientas de conversión de YouTube

`Tools/download-youtube-tools.sh` descarga los binarios que se empaquetan como recursos de Siyahamba:

```bash
./Tools/download-youtube-tools.sh
```

El script fija versión, URL y SHA-256. No acepta un artefacto cuyo hash no coincida.

## Licencias

- `yt-dlp` se distribuye bajo Unlicense. Su distribución oficial incorpora licencias de dependencias en el archivo `THIRD_PARTY_LICENSES.txt` del release. Debe copiarse al paquete de distribución antes de una release.
- Deno se distribuye bajo MIT. Su texto de licencia se conserva en `licenses/Deno-MIT.txt`.
- FFmpeg se compila desde su código fuente oficial con `--disable-gpl --disable-nonfree --enable-version3`; se distribuye bajo LGPL-3.0-or-later.
- LAME se compila estáticamente sólo para habilitar codificación MP3 y se distribuye bajo LGPL-2.0-or-later.

Antes de distribuir Siyahamba fuera de desarrollo, añadir los textos de licencia y la oferta de código fuente requerida para FFmpeg y LAME.

Los binarios generados se guardan en `Siyahamba/Resources/YouTubeTools.bundle/` y no se versionan. Ejecuta el script antes de generar una build distribuible.

## Firma de `yt-dlp`

`yt-dlp_macos` es un ejecutable PyInstaller que extrae y carga un runtime de Python al arrancar. Al firmarlo con Hardened Runtime debe conservar el entitlement `com.apple.security.cs.disable-library-validation`; de lo contrario macOS rechaza el runtime extraído porque no comparte el Team ID del ejecutable.

El workflow aplica `Scripts/yt-dlp.entitlements` antes del archive y vuelve a aplicarlo después de `xcodebuild -exportArchive`, ya que la exportación vuelve a firmar los Mach-O incluidos en Resources. Después verifica la firma y ejecuta `yt-dlp --version` como smoke test antes de notarizar.
