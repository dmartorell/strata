# Lyrics Font Size Controls

## Resumen

Añadir controles de tamaño de fuente a LyricsView mediante un botón `Aa` que abre un popover con opciones de incremento/decremento. Preferencia global persistida con `@AppStorage`.

## Interacción

- Botón `Aa` en la **esquina inferior derecha** de LyricsView
- Estilo visual idéntico al botón de offset (arriba-derecha)
- Al pulsar → popover estilo `LyricsOffsetPopover` con:
  - Título: "Tamaño letra"
  - Valor actual mostrado (ej: "32pt")
  - Botones `A−` / `A+`
  - Botón "Restablecer" que vuelve al default (32pt)

## Niveles de tamaño

| Nivel | Tamaño |
|-------|--------|
| 1 (mín/default) | 32pt |
| 2 | 36pt |
| 3 | 40pt |
| 4 (máx) | 44pt |

- Incrementos de **4pt**
- **No se permite bajar de 32pt** (el tamaño actual hardcoded)
- Máximo: 44pt

## Persistencia

- `@AppStorage("lyrics.fontSize")` con default `32.0`
- Global para todas las canciones

## Comportamiento de texto

- Las líneas largas hacen wrap automático (ya configurado con `multilineTextAlignment(.center)` y `maxWidth: .infinity`)
- El highlight de línea activa funciona correctamente con wrap — se aplica al `Text` completo
- El auto-scroll sigue anclando al `id` de la vista, no a líneas visuales

## Archivos

| Archivo | Acción |
|---------|--------|
| `LyricsFontSizePopover.swift` | **Crear** — popover clonando patrón de `LyricsOffsetPopover` |
| `LyricsView.swift` | **Modificar** — añadir botón `Aa`, pasar fontSize a `LyricLineView`, cambiar ZStack alignment |

## Fuera de alcance

- Pinch-to-zoom
- Tamaño per-song
- Afectar al tamaño de acordes
