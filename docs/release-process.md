# Publicar Siyahamba fuera de App Store

La primera versión con Sparkle es la 1.5. Los usuarios de 1.3/1.4 deben instalar una vez su ZIP manualmente. Desde 1.5, la app se actualiza desde «Buscar actualizaciones…».

## Bootstrap único

1. En Xcode, crea/exporta un certificado `Developer ID Application` `.p12` para el equipo `89ZFGW6H88`.
2. En App Store Connect crea una API key con permiso para notarización y descarga su `.p8`.
3. La clave pública Sparkle está en `project.yml`. La privada vive en el Keychain local, con cuenta `com.siyahamba.client`. Para exportarla al secreto:

```bash
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/.../SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account com.siyahamba.client -x sparkle-private-key
```

4. En GitHub, habilita Pages con GitHub Actions como fuente y crea los secretos: `DEVELOPER_ID_CERTIFICATE_P12_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPSTORE_CONNECT_API_KEY_BASE64`, `APPSTORE_CONNECT_KEY_ID`, `APPSTORE_CONNECT_ISSUER_ID` y `SPARKLE_PRIVATE_ED_KEY`.

Para codificar archivos sin añadir salto de línea:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
cat sparkle-private-key | pbcopy
```

## Release

Incrementa `CFBundleVersion` y `CFBundleShortVersionString` en `project.yml`, ejecuta `xcodegen generate`, valida y publica un tag:

```bash
xcodegen generate
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug test
git commit -am "chore: bump version to X.Y"
git tag vX.Y
git push origin main --tags
```

El workflow firma, notariza, grapa el ticket y publica el ZIP completo en GitHub Releases. Si puede descargar el ZIP de la última release estable, Sparkle genera además un delta desde esa versión y lo publica como otro asset. El ZIP completo siempre queda como fallback para instalaciones nuevas, saltos de versión o fallos del delta. GitHub Pages solo despliega `appcast.xml`.

Si no se puede descargar el ZIP previo o Sparkle no genera un delta, la release continúa con el ZIP completo. Cuando `YouTubeTools.bundle` y su script de descarga no han cambiado, CI exige que cualquier delta generado pese menos del 25% del ZIP completo.
