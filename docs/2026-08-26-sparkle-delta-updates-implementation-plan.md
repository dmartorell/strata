# Sparkle Delta Updates Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Publicar actualizaciones delta de Sparkle desde la release estable inmediatamente anterior, conservando el ZIP completo como fallback.

**Architecture:** El workflow descarga el ZIP de la última GitHub Release antes de crear el appcast. `release_appcast.sh` coloca ese ZIP junto al nuevo para que `generate_appcast` construya el delta, conserva solo la nueva entrada del feed y exporta el ZIP, el delta y el appcast a `dist/`. GitHub Release aloja ambos artefactos y GitHub Pages aloja solo el appcast.

**Tech Stack:** Bash, GitHub Actions, GitHub CLI, Sparkle 2 `generate_appcast`.

---

### Task 1: Generar y exportar artefactos delta

**Files:**
- Modify: `Scripts/release_appcast.sh`

- [x] **Step 1: Añadir la entrada opcional del ZIP anterior**

Añadir tras las variables obligatorias:

```bash
previous_archive="${PREVIOUS_ARCHIVE:-}"
if [[ -n "$previous_archive" && ! -f "$previous_archive" ]]; then
  echo "No se encontró el ZIP de la release anterior: $previous_archive" >&2
  exit 1
fi
```

- [x] **Step 2: Copiar el ZIP anterior al directorio de entrada de Sparkle**

Después de crear `archive`, copiar el archivo solo cuando esté disponible:

```bash
if [[ -n "$previous_archive" ]]; then
  cp "$previous_archive" "$work_dir/archives/"
fi
```

- [x] **Step 3: Limitar el feed a la release nueva y copiar los deltas**

Añadir `--maximum-versions 1` a `generate_appcast`. Tras copiar el ZIP completo, exportar todos los `.delta` generados:

```bash
find "$work_dir/archives" -maxdepth 1 -type f -name '*.delta' -exec cp {} "$output_dir/" \;
```

- [x] **Step 4: Validar sintaxis del script**

Run: `bash -n Scripts/release_appcast.sh`

Expected: exit code 0.

### Task 2: Descargar la release fuente y publicar los deltas

**Files:**
- Modify: `.github/workflows/release.yml`

- [x] **Step 1: Resolver y descargar el ZIP de la última release estable**

Antes de `Crear ZIP y appcast Sparkle`, añadir un paso que use `gh release view --repo "$GITHUB_REPOSITORY" --json tagName --jq .tagName` y `gh release download` con el patrón `Siyahamba-*.zip`. Si no existe release previa o no se puede descargar el asset, debe dejar `PREVIOUS_ARCHIVE` vacío y continuar.

- [x] **Step 2: Detectar si cambiaron las herramientas grandes**

En el mismo paso, comparar el tag anterior con `HEAD` para `Siyahamba/Resources/YouTubeTools.bundle` y `Tools/download-youtube-tools.sh`. Exportar `CHECK_DELTA_SIZE=true` únicamente si no cambió ninguno.

- [x] **Step 3: Entregar el ZIP previo al generador**

Pasar `PREVIOUS_ARCHIVE: ${{ env.PREVIOUS_ARCHIVE }}` al paso `Crear ZIP y appcast Sparkle`.

- [x] **Step 4: Validar el delta publicado antes de crear la GitHub Release**

Tras crear `dist/`, si existe un `.delta`, comprobar que `dist/appcast.xml` lo referencia. Si `CHECK_DELTA_SIZE=true`, comprobar que cada delta pesa menos de un cuarto del ZIP completo. Si no existe delta, registrar que se publicará únicamente el ZIP completo sin fallar el job.

- [x] **Step 5: Adjuntar los deltas a la GitHub Release**

Cambiar `gh release create` para recibir explícitamente `dist/Siyahamba-*.zip` y `dist/*.delta` cuando existan, sin fallar cuando no exista ningún delta.

### Task 3: Documentar el comportamiento de publicación

**Files:**
- Modify: `docs/release-process.md`

- [x] **Step 1: Describir los artefactos Sparkle**

Añadir al apartado `Release` que el workflow toma el ZIP de la última release estable para crear un delta, publica ZIP completo y delta en GitHub Releases, y deja el ZIP completo como fallback para instalaciones nuevas, saltos de versión y fallos de delta.

- [x] **Step 2: Documentar el fallback y el umbral**

Indicar que si no se puede obtener el ZIP anterior o no se genera delta, la release continúa. Cuando `YouTubeTools.bundle` no cambió, CI exige un delta menor al 25% del ZIP completo.

### Task 4: Verificación final

**Files:**
- Test: `Scripts/release_appcast.sh`
- Test: `.github/workflows/release.yml`

- [x] **Step 1: Ejecutar la comprobación de sintaxis**

Run: `bash -n Scripts/release_appcast.sh`

Expected: exit code 0.

- [x] **Step 2: Revisar la configuración de publicación**

Run: `rg -n 'PREVIOUS_ARCHIVE|maximum-versions|delta|gh release download' Scripts/release_appcast.sh .github/workflows/release.yml docs/release-process.md`

Expected: aparecen el ZIP previo, `--maximum-versions 1`, la publicación de `.delta` y la documentación.

- [x] **Step 3: Revisar el diff**

Run: `git diff --check && git diff -- Scripts/release_appcast.sh .github/workflows/release.yml docs/release-process.md`

Expected: sin errores de espacios y con cambios limitados al pipeline de releases y documentación.

- [x] **Step 4: Commit**

```bash
git add Scripts/release_appcast.sh .github/workflows/release.yml docs/release-process.md docs/2026-08-26-sparkle-delta-updates-implementation-plan.md
git commit -m "feat: publish Sparkle delta updates"
```
