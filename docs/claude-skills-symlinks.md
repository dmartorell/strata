# Cómo funcionan los skills y symlinks en Claude Code

## Cadena de symlinks (3 niveles)

1. **`~/.agents/skills/`** — Directorio fuente real donde viven los skills (en tu home)
2. **`~/.claude/skills/`** — Symlinks que apuntan a `~/.agents/skills/*` (nivel global de Claude Code)
3. **`.agents/skills/`** (en el proyecto) — Opcional, solo para skills a nivel de proyecto

## Flujo concreto (ejemplo: SwiftUI)

```
~/.claude/skills/swiftui-expert-skill  →  symlink a  →  ~/.agents/skills/swiftui-expert-skill/
```

## Por qué funciona

- Claude Code escanea `~/.claude/skills/` al iniciar
- Encuentra el symlink (ej. `swiftui-expert-skill`)
- Lo resuelve a `~/.agents/skills/swiftui-expert-skill/`
- Lee el `SKILL.md` de ahí
- Lo registra como skill disponible

## Requisito clave

Cada carpeta dentro de `~/.claude/skills/<nombre>/` debe contener un **`SKILL.md`** (directamente o vía symlink). Claude Code sigue los symlinks sin problema.

## Skills a nivel de proyecto

El directorio `.agents/skills/` dentro de un proyecto es **independiente** de los globales. Claude Code también escanea esa ruta, pero los skills globales vienen de `~/.claude/skills/`.

## Comandos útiles

```bash
# Crear un symlink para un skill nuevo
ln -s ~/.agents/skills/mi-skill ~/.claude/skills/mi-skill

# Verificar que el symlink apunta correctamente
ls -la ~/.claude/skills/

# Ver el contenido real del skill
cat ~/.agents/skills/mi-skill/SKILL.md
```
