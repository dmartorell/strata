# Siyahamba — Video Demo (30s, sin audio)

> Grabado con Screen Studio. Sin música, sin voiceover. Storytelling puramente visual.

---

## Setup previo

| Setting | Valor |
|---------|-------|
| Canción | Cargada con lyrics, acordes y stems. Elegir una con acordes variados (Bm, F#m, G, A...) |
| Librería | 2-3 canciones ya procesadas |
| Font size | 36pt (default) |
| Ventana | ~1280x800 o 1440x900 |
| Finder | Tener una ventana con un .mp3 lista en el borde de pantalla (para Shot 6) |

### Screen Studio — Config global

| Setting | Valor |
|---------|-------|
| Resolución | 1920x1080 (o 4K) |
| FPS | 60 |
| Background | Gradiente `#0a1020` → `#162040` |
| Ventana | Rounded corners 16px + drop shadow |
| Cursor | Highlight sutil (ring), tamaño normal |
| Auto-zoom | ON para shots 2-7 (siguen clicks). **OFF para Shot 1** (no hay clicks — usar zoom manual fijo) |
| Export | MP4 H.264 |

---

## Shot List

### Shot 1 — Hook: Lyrics en vivo (0s → 4s)

**Qué se ve:** Player con modo Lyrics activo. Canción sonando a mitad. Las letras auto-scrollean: línea actual en blanco, próximas en azul claro, pasadas en azul oscuro. Sidebar de stems visible a la izquierda. Transport bar abajo con el slider moviéndose.

**Acción:** Ninguna. Dejar que la app haga su magia.

| Screen Studio | Valor |
|---------------|-------|
| Auto-zoom | **OFF** (no hay clicks en este shot — el auto-zoom no tiene nada que seguir) |
| Zoom | **Manual fijo** 130% centrado en panel de lyrics. Añadir keyframe de zoom en la timeline de Screen Studio. |
| Tilt | 0° (plano, limpio) |
| Velocidad | 1x |

**Atención del espectador:** La transición de colores de las letras scrolleando sobre el fondo azul oscuro. El slider moviéndose da sensación de "en vivo".

**Tip:** Empezar playback 5-10s antes del punto que quieras capturar. Grabar 6+ segundos y recortar a los mejores 4s donde se vea una transición de línea (la línea blanca pasa a la siguiente).

---

### Shot 2 — Stems: Mutear voz + Solo bajo (4s → 8s)

**Qué se ve:** Mismo player. La cámara retrocede ligeramente para incluir el sidebar de stems.

**Acción:**
1. Mover cursor al stem "Voz" → click en botón **M** (Mute). Se pone naranja, la fila se atenúa.
2. Mover cursor al stem "Bajo" → click en botón **S** (Solo). Se pone amarillo, el resto se atenúa.

| Screen Studio | Valor |
|---------------|-------|
| Zoom | De 130% → auto-zoom 160% al sidebar cuando entra el cursor |
| Tilt | 2° eje Y (profundidad sutil en la transición) |
| Velocidad | 1x |

**Atención del espectador:** Los botones M (naranja) y S (amarillo) encendiéndose contra el sidebar oscuro. Dos clicks, dos cambios visuales claros.

**Tip:** Mover cursor deliberadamente, no rápido. Pausar brevemente sobre cada botón antes de clickar para que el auto-zoom se asiente. Tras Solo en Bajo, mantener 1s para que se registre.

---

### Shot 3 — Vista Acordes + Diagrama (8s → 13s)

**Qué se ve:** Click en "Acordes" en el transport bar. La zona central cambia a vista de acordes: nombre grande (128pt bold), acorde siguiente más pequeño (64pt, 50% opacidad), diagrama de guitarra debajo (cuerdas, trastes, dedos).

**Acción:**
1. Click en botón "Acordes" del transport bar
2. Esperar a que cambie el acorde con la canción (animación numericText)
3. Click en el diagrama para ciclar variación de digitación

| Screen Studio | Valor |
|---------------|-------|
| Zoom | Auto-zoom 120% en transport bar para el click → snap a 140% en zona de acordes |
| Tilt | 3° eje X durante la transición de vista |
| Velocidad | 1x para el click, 1.2x durante espera de cambio de acorde |

**Atención del espectador:** El nombre del acorde a 128pt es imposible de ignorar. El diagrama con dedos y trastes comunica instantáneamente "herramienta de guitarra".

**Tip:** Timing: que la canción esté en un punto donde los acordes cambian cada 2-3s. Al clickar el diagrama para ciclar variaciones, la animación es rápida (0.15s) — asegurarse de que el zoom sea suficiente para ver los puntos de dedos recolocarse.

---

### Shot 4 — Rehearsal Sheet + Panel de referencia (13s → 18s)

**Qué se ve:** Click en "Estudio" en transport bar. Cambia a RehearsalSheet: fondo azul oscuro, letras en layout de flujo, nombres de acordes en azul claro posicionados sobre cada palabra.

**Acción:**
1. Click en botón "Estudio" del transport bar
2. Hover cerca del borde inferior de la vista → aparece el panel de referencia (slide-up con todos los acordes únicos de la canción, diagramas 80x80)

| Screen Studio | Valor |
|---------------|-------|
| Zoom | 120% centrado en contenido, 130% cuando aparece el panel |
| Tilt | 0° (mucho contenido, el tilt dificultaría lectura) |
| Velocidad | 1x para el click, 1.5x durante espera del hover (400ms delay), 1x cuando aparece el panel |

**Atención del espectador:** El layout acorde-sobre-letra es la identidad visual única de la rehearsal sheet. El panel deslizándose desde abajo con diagramas miniatura es un momento "wow, eso es útil".

**Tip:** Asegurar que haya suficientes acordes visibles en pantalla. Hover suave hacia los 90px inferiores del área de scroll. Mantener hover 1.5s+ para que el panel aparezca y el espectador lo vea.

---

### Shot 5 — Pitch Shift (18s → 22s)

**Qué se ve:** Click en botón de tono del transport bar. Aparece PitchPopover: "Tono", nombre de la key grande, botones −/+, contador de semitonos.

**Acción:**
1. Click en botón de pitch del transport bar
2. Click en "+" dos veces (la key cambia, los acordes en el fondo se transponen)

| Screen Studio | Valor |
|---------------|-------|
| Zoom | Auto-zoom 180% en el popover (es pequeño, ~200px ancho) |
| Tilt | 0° |
| Velocidad | 1.3x |

**Atención del espectador:** El nombre de la key cambiando (ej. "D" → "E"). Si los nombres de acordes del fondo también se actualizan, es un detalle potente.

**Tip:** Tener "Mostrar transpuesto" ya activado antes de grabar. Así al pulsar "+", los acordes del rehearsal sheet cambian visiblemente. Cerrar el popover al final del shot clickando fuera.

---

### Shot 6 — Flashback: Importar canción (22s → 27s)

**Qué se ve:** Navegar a la librería (botón "Biblioteca" con chevron.left). Tabla con columnas Título, Artista, Tono, Duración. Arrastrar archivo desde Finder al drop zone (borde punteado). Badge púrpura con spinner: "Subiendo archivo..." → "Separando stems..." → "Detectando acordes..." → verde "Finalizado".

**Acción:**
1. Click en botón back
2. Drag de archivo .mp3 desde Finder al drop zone
3. Proceso en fast-forward

| Screen Studio | Valor |
|---------------|-------|
| Zoom | 100% para vista librería → auto-zoom 140% en drop zone durante drag → 150% en badge de status |
| Tilt | 3° eje Y durante el drag |
| Velocidad | 1x para el drag, luego **3-4x fast-forward** durante el procesamiento |

**Atención del espectador:** El drag-and-drop es universalmente entendido. Los badges con fases ("Separando stems...", "Detectando acordes...") cuentan lo que la app hace bajo el capó. El badge verde al final es la resolución.

**Tip:** Shot más difícil de timing. Pre-posicionar Finder con el archivo. Usar archivo pequeño (MP3 de 2 min) para que el proceso no tarde mucho. Grabar el proceso completo y aplicar speed ramp en Screen Studio.

---

### Shot 7 — Payoff: Player completo (27s → 30s)

**Qué se ve:** Badge verde visible. Doble-click en la canción recién importada. Se abre el player completo: sidebar de stems a la izquierda, lyrics scrolleando en el centro, transport bar abajo. Todo poblado y activo.

**Acción:** Doble-click en la fila de la canción en la tabla.

| Screen Studio | Valor |
|---------------|-------|
| Zoom | 140% en la fila de la tabla → zoom-out a 90% revelando el player completo |
| Tilt | 2° → settling a 0° (efecto "aterrizaje") |
| Velocidad | 1x |

**Atención del espectador:** El zoom-out revelando la interfaz completa es la impresión final. El espectador ve todo junto: stems, lyrics, transport. "Arrastro un archivo y obtengo todo esto."

**Tip:** Asegurar que el playback empieza inmediatamente (o pulsar play al instante). Las lyrics deben scrollear, el slider moverse — la app tiene que sentirse viva. Mantener el frame final 1.5s como beauty shot. Si aparece el ProgressView de carga ("Cargando..."), recortarlo.

---

## Timeline resumen

```
0s        4s        8s        13s       18s       22s       27s   30s
|—— 1 ——|—— 2 ——|——— 3 ———|——— 4 ———|—— 5 ——|——— 6 ———|— 7 —|
 Lyrics   Stems    Acordes   Rehearsal  Pitch    Import    Full
 scroll   M/S      diagram   sheet+ref  shift    drag&drop player
```

## Si 30s es muy justo

Comprimir por orden de prioridad:
1. **Shot 5** (pitch): reducir a 3s, solo un click en "+"
2. **Shot 6** (import): fast-forward más agresivo (5-6x)
3. **Shot 4** (rehearsal): quitar hover del panel, solo mostrar layout 3s

**NO tocar** shots 1, 2, 3 ni 7 — llevan la narrativa central.

---

## Nota sobre auto-zoom

Screen Studio auto-zoom sigue tus **clicks y movimientos de cursor**. Donde hagas click, ahí hace zoom automáticamente.

- **Shots 2-7:** Auto-zoom ON. Todos tienen clicks que guían el zoom de forma natural.
- **Shot 1:** Auto-zoom OFF. No hay clicks (solo lyrics scrolleando). Usar zoom manual fijo con keyframe en la timeline de Screen Studio.

**Cómo funciona en la práctica:** Graba siempre a pantalla completa. Los zooms (automáticos o manuales) se aplican después en el editor de Screen Studio sobre la grabación ya hecha. Si el auto-zoom no encuadra exactamente como quieres, ajusta manualmente con keyframes.
