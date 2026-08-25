# Autoactualización notarizada Design

**Estado:** aprobado

## Objetivo

Permitir que una instalación existente compruebe, descargue e instale actualizaciones desde la propia app, sin que macOS muestre el aviso de app no segura.

## Decisión

Se usará Sparkle 2 con GitHub Actions y GitHub Releases en el repositorio público `dmartorell/strata`.

Cada tag `vX.Y` ejecutará un workflow que archive la app, la firme con `Developer ID Application`, la notarice con Apple, la compacte en ZIP compatible con Sparkle, genere el appcast firmado y publique el ZIP en un GitHub Release. El appcast se alojará en GitHub Pages del mismo repositorio, en una URL estable HTTPS.

## Distribución y seguridad

- La app cambiará de firma de desarrollo a `Developer ID Application` para los artefactos de distribución. La firma de desarrollo se mantiene para Debug local.
- El workflow usa un certificado Developer ID exportado y una clave de App Store Connect para `notarytool`. Ambos quedan únicamente como secretos de GitHub Actions.
- Sparkle firma cada actualización con una clave EdDSA propia. La clave pública se integra en la app. La privada queda como secreto de GitHub Actions.
- La app se envía al notario de Apple antes de publicarse. El ZIP final contiene la app ya firmada y notarizada.
- GitHub Pages y Releases son públicos. El repositorio también será público, según decisión del usuario.

## Experiencia de usuario

- Al arrancar, Sparkle busca actualizaciones en segundo plano una vez al día.
- El menú de la app incluye «Buscar actualización…» para una comprobación manual.
- Si hay versión nueva, Sparkle muestra su ventana nativa con notas de versión y ofrece descargar e instalar.
- La instalación reemplaza la app al cerrarse y vuelve a abrirla. La biblioteca en `~/Music/Siyahamba` no forma parte del bundle, así que no se modifica.
- Si no hay red o el feed no responde, la comprobación automática no interrumpe. La comprobación manual muestra un error localizado.

## Componentes

| Componente | Responsabilidad |
|---|---|
| `Sparkle.framework` | Consulta del appcast, verificación EdDSA, descarga e instalación segura. |
| `AppDelegate` o coordinador de actualización | Conserva el `SPUStandardUpdaterController`, inicia la comprobación automática y expone la acción manual a SwiftUI. |
| `project.yml` | Declara Sparkle y configura `SUFeedURL` y la clave pública EdDSA en el Info.plist generado. |
| `release.yml` | Compila Release, firma, notariza, genera ZIP/appcast, crea el Release y publica el appcast en GitHub Pages. |
| GitHub Secrets | Certificado Developer ID, contraseña de su clave privada, credenciales de notarytool y clave privada EdDSA de Sparkle. |

## Flujo de publicación

1. Se actualiza `CFBundleShortVersionString` y se crea/pushea un tag `vX.Y`.
2. GitHub Actions construye un archive Release con `xcodebuild archive`.
3. El workflow firma la app con Developer ID y hardened runtime, ejecuta `notarytool submit --wait` y hace stapling del ticket.
4. Sparkle genera un ZIP y un item firmado para `appcast.xml` con la versión, URL del asset y notas de la Release.
5. El workflow publica el ZIP en GitHub Releases y el appcast en GitHub Pages.
6. Las instalaciones consultan el appcast estable, validan firma y descargan el ZIP.

## Límites

- No se implementa actualización delta ni canales beta. Cada release descarga el ZIP completo.
- No se usa Mac App Store ni autenticación de usuario para actualizar.
- La primera instalación sigue siendo manual. A partir de esa versión, las siguientes son in-app.
- La app debe instalarse en una ubicación que el usuario pueda modificar, normalmente `/Applications`. Si está ejecutándose desde una carpeta protegida o en solo lectura, Sparkle mostrará su error estándar.

## Validación

- CI verifica que el archive esté firmado con Developer ID, que Gatekeeper lo acepte y que el ticket de notarización quede grapado.
- Se publica primero un release de prueba con una versión superior y se instala sobre una copia de la versión anterior.
- Se comprueba que Sparkle detecta la versión, instala el ZIP, reinicia la app y conserva una biblioteca existente.
- Se verifica en un Mac sin Xcode que Gatekeeper abre la app sin aviso de desarrollador no identificado.
