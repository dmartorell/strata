---
phase: 03-swift-client-auth
plan: 03
subsystem: auth
tags: [swift, swiftui, observable, jwt, jwtdecode, keychain, macos, tdd]

requires:
  - phase: 03-swift-client-auth
    plan: 01
    provides: APIClient (login, renewToken) + HTTPTransport protocol
  - phase: 03-swift-client-auth
    plan: 02
    provides: KeychainService (save/load/delete JWT) + POST /auth/renew

provides:
  - AuthViewModel (@Observable @MainActor) con checkStoredToken, login, logout, handleUnauthorized, silentRenew
  - KeychainServiceProtocol + APIClientProtocol para testability via inyeccion de dependencias
  - LoginView (SecureField contrasena, ProgressView, error generico, Enter shortcut)
  - StrataApp root auth gate: @State authViewModel, if/else isAuthenticated -> ContentView/LoginView
  - 8 unit tests AuthViewModelTests con MockKeychainService y MockAPIClient (sin Keychain ni red real)
  - Flujo end-to-end verificado manualmente: login, persistencia 90 dias, renovacion silenciosa

affects:
  - 04-onward (AuthViewModel es la fuente de verdad de sesion para todas las vistas futuras)

tech-stack:
  added:
    - JWTDecode.swift 4.0 (Auth0, ya anadida en 03-01) — decode(jwt:) para leer expiresAt
    - Observation framework (@Observable, macOS 14)
  patterns:
    - KeychainServiceProtocol + APIClientProtocol: protocolos minimos para inyeccion en tests
    - "@Observable @MainActor" para ViewModels de SwiftUI (patron macOS 14, no ObservableObject)
    - "@State private var authViewModel" en App body (no @StateObject)
    - silentRenew con guard isRenewing: anti-race condition para renovaciones paralelas
    - checkStoredToken sincrono en init: sesion restaurada antes del primer frame
    - Error generico en LoginView: cualquier fallo -> "Contrasena incorrecta" (sin distinguir red de credenciales)

key-files:
  created:
    - StrataClient/Auth/AuthViewModel.swift
    - StrataClientTests/AuthViewModelTests.swift
  modified:
    - StrataClient/Auth/LoginView.swift (implementado desde placeholder)
    - StrataClient/App/StrataApp.swift (root auth gate + ventana 900x600)
    - StrataClient.xcodeproj/project.pbxproj (xcodegen regenerado para incluir AuthViewModelTests)

key-decisions:
  - "KeychainServiceProtocol + APIClientProtocol en lugar de subclassing: Swift 5.9 + @unchecked Sendable en mocks — mas idiomatico que herencia para tipos final"
  - "@Observable @MainActor AuthViewModel: @Observable requiere MainActor en macOS 14 para propagar cambios a SwiftUI correctamente; @MainActor elimina data races en propiedades observadas"
  - "checkStoredToken sincrono en init: el token se carga del Keychain antes del primer render, evitando el flash de LoginView al relanzar con sesion valida"
  - "silentRenew con isRenewing flag: evita renovaciones paralelas sin necesidad de actor — suficiente para un unico usuario con una sesion"
  - "Ventana 900x600 por defecto con resizability .contentMinSize: tamano util para ContentView sin forzar al usuario a redimensionar"

patterns-established:
  - "Protocol injection en AuthViewModel: KeychainServiceProtocol + APIClientProtocol inyectados en init — patron para fases futuras con AuthViewModel"
  - "@Observable @MainActor: patron estandar de ViewModel en este proyecto — NO usar ObservableObject/StateObject"
  - "Error mapping en LoginView: catch { errorMessage = 'Contrasena incorrecta' } — oculta detalles de red al usuario"

requirements-completed:
  - AUTH-01
  - AUTH-02
  - AUTH-03
  - AUTH-04

duration: ~75min
completed: 2026-03-03
---

# Phase 03 Plan 03: AuthViewModel + LoginView + StrataApp Summary

**@Observable AuthViewModel con checkStoredToken sincrono, LoginView SecureField-only y StrataApp root auth gate — flujo end-to-end verificado: login real funciona, sesion persiste 90 dias via Keychain.**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-03-03T21:20:19Z
- **Completed:** 2026-03-03T21:45:00Z
- **Tasks:** 3/3 completadas
- **Files modified:** 5 + 2 fixes adicionales

## Accomplishments

- AuthViewModel @Observable @MainActor: fuente unica de verdad para isAuthenticated/token
- checkStoredToken sincrono en init: sesion restaurada del Keychain antes del primer render (sin flash de LoginView)
- silentRenew con guard isRenewing: tokens con < 7 dias se renuevan en background sin interrumpir al usuario
- 8 unit tests con mocks completos (MockKeychainService, MockAPIClient) — sin Keychain real ni red
- LoginView: SecureField, ProgressView en carga, error generico, Enter shortcut
- StrataApp: @State authViewModel (no @StateObject), if/else en WindowGroup, ventana 900x600 por defecto
- Checkpoint humano aprobado: login con contrasena correcta funciona, error con contrasena incorrecta, sesion persiste entre relanzamientos

## Task Commits

1. **Task 1: AuthViewModel @Observable + AuthViewModelTests (TDD)** - `3be8f61` (feat)
2. **Task 2: LoginView + StrataApp root auth gate** - `67bf999` (feat)
3. **Task 3: Verificacion end-to-end** - aprobada (checkpoint humano)
4. **Fix: URL base Modal corregida** - `3d271ca` (fix — dani-martorell, no danielmartorell)
5. **Fix: Ventana 900x600 por defecto** - `ba86b9d` (fix — resizability .contentMinSize)

## Files Created/Modified

- `StrataClient/Auth/AuthViewModel.swift` — @Observable AuthViewModel con protocolos, checkStoredToken, login, logout, handleUnauthorized, silentRenew
- `StrataClientTests/AuthViewModelTests.swift` — 8 tests con MockKeychainService y MockAPIClient
- `StrataClient/Auth/LoginView.swift` — SecureField, ProgressView, error generico, keyboard shortcut
- `StrataClient/App/StrataApp.swift` — root auth gate con @State authViewModel, ventana 900x600
- `StrataClient.xcodeproj/project.pbxproj` — regenerado con xcodegen (incluye AuthViewModelTests)

## Decisions Made

- **KeychainServiceProtocol + APIClientProtocol:** Protocolos minimos para inyeccion de dependencias en tests, sin afectar los tipos concretos. Swift 5.9 `any Protocol` con `@unchecked Sendable` en los mocks.
- **@Observable @MainActor:** macOS 14 requiere @MainActor en @Observable classes para propagar cambios a SwiftUI. Elimina data races en propiedades observadas sin overhead adicional.
- **checkStoredToken sincrono:** Cargar el token del Keychain en init() garantiza que `isAuthenticated` tiene el valor correcto antes del primer render de SwiftUI — evita el flash de LoginView al relanzar con sesion valida.
- **Ventana 900x600:** .windowResizability(.contentMinSize) permite al usuario redimensionar libremente mientras garantiza un tamano inicial util para ContentView.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] URL base Modal corregida**
- **Found during:** Task 3 (verificacion end-to-end)
- **Issue:** APIClient usaba `danielmartorell` en la URL de Modal pero el workspace real es `dani-martorell` — login fallaba con 404
- **Fix:** Actualizada URL base a `https://dani-martorell--strata-web.modal.run`
- **Files modified:** `StrataClient/Network/APIClient.swift`
- **Verification:** Login end-to-end funciona con la URL correcta
- **Committed in:** `3d271ca`

**2. [Rule 2 - Missing Critical] Tamano inicial de ventana 900x600**
- **Found during:** Task 3 (verificacion end-to-end)
- **Issue:** `.windowResizability(.contentSize)` fijaba el tamano a las dimensiones del LoginView (360x280) y no permitia redimensionar tras el login — ContentView quedaba muy pequena
- **Fix:** Cambiado a `.windowResizability(.contentMinSize)` con `.defaultSize(width: 900, height: 600)`
- **Files modified:** `StrataClient/App/StrataApp.swift`
- **Verification:** Ventana aparece en 900x600 tras login, redimensionable por el usuario
- **Committed in:** `ba86b9d`

---

**Total deviations:** 2 auto-fixed (1 bug URL, 1 missing UX critico)
**Impact on plan:** Ambos fixes necesarios para funcionalidad correcta. Sin scope creep.

## Issues Encountered

- Firma Keychain con "Sign to Run Locally" (ad-hoc) causa OSStatus -25293 — resuelto configurando Apple ID en Signing & Capabilities (documentado en plan como user_setup)

## User Setup Required

**Configuracion de firma Xcode requerida (completada por el usuario):**
- Apple ID anadido en Xcode Settings -> Accounts
- Signing & Capabilities -> Team: Apple ID (Personal Team)
- Necesario para que Keychain funcione correctamente entre rebuilds (ACL estable)

## Next Phase Readiness

- Flujo de autenticacion completo y verificado end-to-end
- AuthViewModel es la base de sesion para todas las vistas futuras de Phase 4+
- All 25 unit tests pasan (12 NetworkTests + 5 KeychainTests + 8 AuthViewModelTests)
- Phase 4 (UI/UX principal) puede comenzar — AuthViewModel esta disponible via @Environment

---
*Phase: 03-swift-client-auth*
*Completed: 2026-03-03*

## Self-Check: PASSED

- FOUND: StrataClient/Auth/AuthViewModel.swift
- FOUND: StrataClientTests/AuthViewModelTests.swift
- FOUND: StrataClient/Auth/LoginView.swift
- FOUND: StrataClient/App/StrataApp.swift
- Commits verificados: 3be8f61, 67bf999, 3d271ca, ba86b9d
