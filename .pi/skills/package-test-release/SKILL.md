---
name: package-test-release
disable-model-invocation: true
description: Genera un ZIP Release de Siyahamba para un usuario de prueba.
---

# Package Test Release

Desde la raíz del repositorio:

1. Lee `CFBundleShortVersionString` de `Siyahamba/Info.plist` con `PlistBuddy`. Usa ese valor como `VERSION`.
2. Elimina solo `build/Release-distribution` y crea el directorio de nuevo.
3. Compila una Release universal:
   ```bash
   xcodebuild -project Siyahamba.xcodeproj \
     -scheme Siyahamba \
     -configuration Release \
     -derivedDataPath build/Release-distribution \
     build
   ```
   La compilación debe terminar con `BUILD SUCCEEDED`.
4. Localiza `Siyahamba.app` en `build/Release-distribution/Build/Products/Release/`. Crea `dist/` si no existe y genera `dist/Siyahamba-${VERSION}.zip` con:
   ```bash
   ditto -c -k --sequesterRsrc --keepParent \
     "$APP_PATH" "dist/Siyahamba-${VERSION}.zip"
   ```
   Reemplaza el ZIP previo de esa misma versión.
5. Verifica el ZIP con `unzip -t`, la firma con `codesign --verify --deep --strict --verbose=2` y que el ejecutable tenga `arm64` y `x86_64` usando `file`.
6. Devuelve el path absoluto del ZIP, su tamaño y su SHA-256.

La Release actual usa firma de desarrollo. Indica que no está notarizada y que el usuario de prueba puede necesitar autorizar su apertura manualmente en macOS.
