# Autoactualización notarizada Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distribuir versiones notarizadas desde GitHub Releases y actualizar instalaciones de Siyahamba desde la propia app con Sparkle.

**Architecture:** La app integra Sparkle 2 y declara un feed HTTPS estable de GitHub Pages. Un workflow de tags construye el archive Release, lo firma con Developer ID, lo notariza, firma el ZIP para Sparkle, publica el Release y actualiza el appcast de Pages. El código no contiene credenciales. GitHub Secrets contiene las claves privadas.

**Tech Stack:** Swift 5.9, SwiftUI macOS 14+, Sparkle 2.9+, XcodeGen, GitHub Actions macOS, `xcodebuild`, `notarytool`, GitHub Pages.

---

## Precondiciones de distribución

El Account Holder debe configurar estos secretos de Actions antes de publicar el primer tag:

| Secreto | Contenido |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | `Developer ID Application` exportado como `.p12`, codificado con `base64`. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Contraseña del `.p12`. |
| `APPSTORE_CONNECT_API_KEY_BASE64` | Archivo `.p8` de una API key de App Store Connect, codificado con `base64`. |
| `APPSTORE_CONNECT_KEY_ID` | Key ID de la API key. |
| `APPSTORE_CONNECT_ISSUER_ID` | Issuer ID de App Store Connect. |
| `SPARKLE_PRIVATE_ED_KEY` | Clave privada creada una vez con `generate_keys`, exportada para CI. |

La clave pública devuelta por `generate_keys` no es secreta. Se añadirá a `SUPublicEDKey` antes de construir la primera versión con Sparkle. GitHub Pages debe habilitarse para desplegar desde el workflow.

## File map

- Modify: `project.yml` — dependencia Sparkle, Info.plist de actualización y configuración Release.
- Modify: `Siyahamba/App/SiyahambaApp.swift` — mantener el updater y exponer «Buscar actualizaciones…».
- Create: `.github/workflows/release.yml` — pipeline de firma, notarización, Release y Pages.
- Create: `Scripts/release_appcast.sh` — crea el ZIP Sparkle y actualiza el feed sin exponer la clave en argumentos.
- Create: `Scripts/export-options-developer-id.plist` — configuración de exportación Developer ID.
- Create: `docs/release-process.md` — bootstrap de claves y proceso de release.
- Modify: `SiyahambaTests/Info.plist`, `Siyahamba/Info.plist`, `Siyahamba.xcodeproj/project.pbxproj` — resultados de `xcodegen generate`.

### Task 1: Integrar el cliente Sparkle

**Files:**
- Modify: `project.yml`
- Modify: `Siyahamba/App/SiyahambaApp.swift`
- Modify: `Siyahamba/Info.plist`
- Modify: `SiyahambaTests/Info.plist`
- Modify: `Siyahamba.xcodeproj/project.pbxproj`

- [ ] **Step 1: Declarar Sparkle en XcodeGen**

Añadir al bloque `packages`:

```yaml
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.9.5
```

Añadir la dependencia de producto al target `Siyahamba`:

```yaml
      - package: Sparkle
```

Añadir estas propiedades al Info.plist del target de app. `SUPublicEDKey` se rellena con la clave pública real durante el bootstrap y no debe ser un secreto:

```yaml
        SUFeedURL: https://dmartorell.github.io/strata/appcast.xml
        SUPublicEDKey: <clave-pública-EdDSA-de-Sparkle>
        SUEnableAutomaticChecks: true
```

Mantener `CFBundleVersion` como entero monotónico. Para el primer release Sparkle, cambiarlo de `1` a `2`; cada release posterior incrementa este número y actualiza `CFBundleShortVersionString`.

- [ ] **Step 2: Regenerar el proyecto**

Run: `xcodegen generate`

Expected: `Siyahamba.xcodeproj` referencia el paquete Sparkle y los dos Info.plist generados conservan las versiones configuradas.

- [ ] **Step 3: Conservar el controlador durante toda la vida de la app**

En `Siyahamba/App/SiyahambaApp.swift`, importar Sparkle y añadir una propiedad no observable:

```swift
private let updaterController: SPUStandardUpdaterController
```

Inicializarla al comienzo de `init()`:

```swift
updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

Añadir un comando de aplicación después de `.appInfo`:

```swift
.commands {
    CommandGroup(after: .appInfo) {
        Button("Buscar actualizaciones…") {
            updaterController.checkForUpdates(nil)
        }
    }
}
```

No iniciar comprobaciones manuales desde `.task`. Sparkle programa su ciclo diario automáticamente.

- [ ] **Step 4: Compilar y validar el bundle**

Run:

```bash
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug build
plutil -extract SUFeedURL raw -o - build/Run/Build/Products/Debug/Siyahamba.app/Contents/Info.plist
```

Expected: build correcto y la URL exacta del appcast.

- [ ] **Step 5: Ejecutar la suite**

Run: `xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug test`

Expected: todos los tests pasan.

- [ ] **Step 6: Commit**

```bash
git add project.yml Siyahamba/App/SiyahambaApp.swift Siyahamba/Info.plist SiyahambaTests/Info.plist Siyahamba.xcodeproj/project.pbxproj
git commit -m "feat: add Sparkle update client"
```

### Task 2: Empaquetar, firmar y generar appcast en CI

**Files:**
- Create: `Scripts/export-options-developer-id.plist`
- Create: `Scripts/release_appcast.sh`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Crear export options de Developer ID**

Crear `Scripts/export-options-developer-id.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key><string>export</string>
  <key>method</key><string>developer-id</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>89ZFGW6H88</string>
</dict>
</plist>
```

- [ ] **Step 2: Crear el script de publicación de Sparkle**

Crear `Scripts/release_appcast.sh`, ejecutable. Debe recibir `APP_PATH`, `RELEASE_VERSION`, `BUILD_NUMBER`, `RELEASE_URL`, `APPCAST_PATH` y leer la clave privada desde `SPARKLE_PRIVATE_ED_KEY` por stdin temporal con permisos `600`. Debe:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${APP_PATH:?}"
: "${RELEASE_VERSION:?}"
: "${BUILD_NUMBER:?}"
: "${RELEASE_URL:?}"
: "${APPCAST_PATH:?}"
: "${SPARKLE_PRIVATE_ED_KEY:?}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
archive="$workdir/Siyahamba-${RELEASE_VERSION}.zip"
key="$workdir/sparkle-private-key"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$key"
chmod 600 "$key"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$archive"
signature="$("$SPARKLE_SIGN_UPDATE" --ed-key-file "$key" "$archive")"
length="$(stat -f '%z' "$archive")"
```

El resto del script debe escribir un `appcast.xml` RSS válido con el item nuevo primero, `sparkle:version` igual a `BUILD_NUMBER`, `sparkle:shortVersionString` igual a `RELEASE_VERSION`, `sparkle:minimumSystemVersion` igual a `14.0.0`, la URL de GitHub Release y los atributos XML que devuelve `sign_update`. Debe conservar items anteriores de `APPCAST_PATH` si existe. El script copia el ZIP a `$GITHUB_WORKSPACE/dist/` para que el workflow lo suba como asset.

- [ ] **Step 3: Crear el workflow de tags**

Crear `.github/workflows/release.yml` con trigger `push.tags: ["v*"]`, permisos `contents: write`, `pages: write`, `id-token: write`, runner `macos-15` y estos pasos:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
- uses: actions/configure-pages@v5
- name: Importar certificado Developer ID
  env:
    CERTIFICATE_BASE64: ${{ secrets.DEVELOPER_ID_CERTIFICATE_P12_BASE64 }}
    CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
  run: |
    echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
    security create-keychain -p temporary build.keychain
    security unlock-keychain -p temporary build.keychain
    security import certificate.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    security list-keychains -d user -s build.keychain
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k temporary build.keychain
- name: Archive y exportar
  run: |
    xcodebuild -resolvePackageDependencies -project Siyahamba.xcodeproj -scheme Siyahamba
    xcodebuild archive -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Release -archivePath "$PWD/build/Siyahamba.xcarchive" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=89ZFGW6H88
    xcodebuild -exportArchive -archivePath "$PWD/build/Siyahamba.xcarchive" -exportPath "$PWD/build/export" -exportOptionsPlist Scripts/export-options-developer-id.plist
- name: Notarizar y grapar
  env:
    API_KEY_BASE64: ${{ secrets.APPSTORE_CONNECT_API_KEY_BASE64 }}
    KEY_ID: ${{ secrets.APPSTORE_CONNECT_KEY_ID }}
    ISSUER_ID: ${{ secrets.APPSTORE_CONNECT_ISSUER_ID }}
  run: |
    echo "$API_KEY_BASE64" | base64 --decode > AuthKey.p8
    ditto -c -k --sequesterRsrc --keepParent build/export/Siyahamba.app build/notarization.zip
    xcrun notarytool submit build/notarization.zip --key AuthKey.p8 --key-id "$KEY_ID" --issuer "$ISSUER_ID" --wait
    xcrun stapler staple build/export/Siyahamba.app
    spctl --assess --type execute --verbose build/export/Siyahamba.app
```

Después debe descargar el appcast previo de GitHub Pages si existe, localizar `sign_update` dentro de los artifacts de Sparkle, ejecutar `Scripts/release_appcast.sh`, crear el GitHub Release con `gh release create`, y desplegar el directorio que contiene `appcast.xml` mediante `actions/upload-pages-artifact@v3` y `actions/deploy-pages@v4`.

- [ ] **Step 4: Validar sintaxis y permisos**

Run:

```bash
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/release.yml')"
bash -n Scripts/release_appcast.sh
plutil -lint Scripts/export-options-developer-id.plist
```

Expected: los tres comandos terminan correctamente.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml Scripts/export-options-developer-id.plist Scripts/release_appcast.sh
git commit -m "ci: publish notarized Sparkle releases"
```

### Task 3: Documentar bootstrap y validar una actualización real

**Files:**
- Create: `docs/release-process.md`

- [ ] **Step 1: Documentar la generación inicial de claves**

Escribir instrucciones exactas para:

```bash
# Tras resolver Sparkle, ejecutar una vez en un Mac seguro:
path/to/Sparkle/bin/generate_keys
# Exportar la clave privada únicamente para GitHub Secret:
path/to/Sparkle/bin/generate_keys -x sparkle-private-key
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Documentar que la salida pública de `generate_keys` va a `SUPublicEDKey` y que el archivo privado exportado se guarda como `SPARKLE_PRIVATE_ED_KEY`, sin hacer commit de ninguno.

- [ ] **Step 2: Documentar el proceso de release**

Incluir:

```bash
# Cambiar ambos valores en project.yml, regenerar y validar.
xcodegen generate
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug test
git commit -am "chore: bump version to X.Y"
git tag vX.Y
git push origin main --tags
```

El documento debe indicar que el primer ZIP con Sparkle se distribuye manualmente a usuarios de 1.3/1.4. Las actualizaciones in-app empiezan a funcionar tras instalar esa versión.

- [ ] **Step 3: Validar un release de prueba**

Con secretos cargados y Pages activo, crear un tag de prueba con versión y build superiores. Verificar:

```bash
codesign --verify --deep --strict --verbose=2 build/export/Siyahamba.app
spctl --assess --type execute --verbose build/export/Siyahamba.app
xcrun stapler validate build/export/Siyahamba.app
curl --fail https://dmartorell.github.io/strata/appcast.xml
```

Instalar la versión anterior en `/Applications`, abrirla, usar «Buscar actualizaciones…», instalar la nueva y comprobar que `~/Music/Siyahamba/library.json` no cambió.

- [ ] **Step 4: Commit**

```bash
git add docs/release-process.md
git commit -m "docs: add notarized release process"
```

## Self-review

- Cobertura: Sparkle en cliente, firma Developer ID, notarización Apple, ZIP firmado EdDSA, appcast HTTPS, publicación GitHub, actualización manual y automática, y preservación de biblioteca.
- Dependencia externa: Apple y GitHub Secrets no pueden configurarse desde código. El workflow falla de forma segura sin ellos y el documento identifica cada valor.
- No se añaden canales beta, deltas, telemetría ni servidor propio.
