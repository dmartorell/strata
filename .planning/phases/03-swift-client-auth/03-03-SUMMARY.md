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
  - KeychainServiceProtocol + APIClientProtocol para testability via inyección de dependencias
  - LoginView (SecureField contraseña, ProgressView, error genérico, Enter shortcut)
  - StrataApp root auth gate: @State authViewModel, if/else isAuthenticated → ContentView/LoginView
  - 8 unit tests AuthViewModelTests con MockKeychainService y MockAPIClient (sin Keychain ni red real)

affects:
  - 04-onward (AuthViewModel es la fuente de verdad de sesión para todas las vistas futuras)

tech-stack:
  added:
    - JWTDecode.swift 4.0 (Auth0, ya añadida en 03-01) — decode(jwt:) para leer expiresAt
    - Observation framework (@Observable, macOS 14)
  patterns:
    - KeychainServiceProtocol + APIClientProtocol: protocolos mínimos para inyección en tests
    - "@Observable @MainActor" para ViewModels de SwiftUI (patrón macOS 14, no ObservableObject)
    - "@State private var authViewModel" en App body (no @StateObject)
    - silentRenew con guard isRenewing: anti-race condition para renovaciones paralelas
    - checkStoredToken síncrono en init: sesión restaurada antes del primer frame
    - Error genérico en LoginView: cualquier fallo → "Contraseña incorrecta" (sin distinguir red de credenciales)

key-files:
  created:
    - StrataClient/Auth/AuthViewModel.swift
    - StrataClientTests/AuthViewModelTests.swift
  modified:
    - StrataClient/Auth/LoginView.swift (implementado desde placeholder)
    - StrataClient/App/StrataApp.swift (root auth gate desde placeholder)
    - StrataClient.xcodeproj/project.pbxproj (xcodegen regenerado para incluir AuthViewModelTests)

key-decisions:
  - "KeychainServiceProtocol + APIClientProtocol en lugar de subclassing: Swift 5.9 + @unchecked Sendable en mocks — más idiomático que herencia para tipos final"
  - "@Observable @MainActor AuthViewModel: @Observable requiere MainActor en macOS 14 para propagar cambios a SwiftUI correctamente; @MainActor elimina data races en propiedades observadas"
  - "checkStoredToken síncrono en init: el token se carga del Keychain antes del primer render, evitando el flash de LoginView al relanzar con sesión válida"
  - "silentRenew con isRenewing flag: evita renovaciones paralelas sin necesidad de actor — suficiente para un único usuario con una sesión"

patterns-established:
  - "Protocol injection en AuthViewModel: KeychainServiceProtocol + APIClientProtocol inyectados en init — patrón para fases futuras con AuthViewModel"
  - "@Observable @MainActor: patrón estándar de ViewModel en este proyecto — NO usar ObservableObject/StateObject"
  - "Error mapping en LoginView: catch { errorMessage = 'Contraseña incorrecta' } — oculta detalles de red al usuario"

requirements-completed:
  - AUTH-01
  - AUTH-02
  - AUTH-03
  - AUTH-04

duration: ~65min
completed: 2026-03-03
---

# Phase 03 Plan 03: AuthViewModel + LoginView + StrataApp Summary

**@Observable AuthViewModel con checkStoredToken síncrono en init, silentRenew < 7 días, LoginView SecureField-only y StrataApp root auth gate — flujo end-to-end pendiente de verificación manual.**

## Performance

- **Duration:** ~65 min (Tasks 1-2 completadas; Task 3 checkpoint humano pendiente)
- **Started:** 2026-03-03T21:20:19Z
- **Completed:** 2026-03-03T21:22:46Z (Tasks 1-2)
- **Tasks:** 2/3 completadas (Task 3 es checkpoint humano)
- **Files modified:** 5

## Accomplishments

- AuthViewModel @Observable @MainActor: fuente única de verdad para isAuthenticated/token
- checkStoredToken síncrono en init: sesión restaurada del Keychain antes del primer render (sin flash de LoginView)
- silentRenew con guard isRenewing: tokens con < 7 días se renuevan en background sin interrumpir al usuario
- 8 unit tests con mocks completos (MockKeychainService, MockAPIClient) — sin Keychain real ni red
- LoginView: SecureField, ProgressView en carga, error genérico, Enter shortcut
- StrataApp: @State authViewModel (no @StateObject), if/else en WindowGroup

## Task Commits

1. **Task 1: AuthViewModel @Observable + AuthViewModelTests (TDD)** - `3be8f61` (feat)
2. **Task 2: LoginView + StrataApp root auth gate** - `67bf999` (feat)
3. **Task 3: Verificación end-to-end** - pendiente checkpoint humano

## Files Created/Modified

- `StrataClient/Auth/AuthViewModel.swift` — @Observable AuthViewModel con protocolos, checkStoredToken, login, logout, handleUnauthorized, silentRenew
- `StrataClientTests/AuthViewModelTests.swift` — 8 tests con MockKeychainService y MockAPIClient
- `StrataClient/Auth/LoginView.swift` — SecureField, ProgressView, error genérico, keyboard shortcut
- `StrataClient/App/StrataApp.swift` — root auth gate con @State authViewModel
- `StrataClient.xcodeproj/project.pbxproj` — regenerado con xcodegen (incluye AuthViewModelTests)

## Decisions Made

- **KeychainServiceProtocol + APIClientProtocol:** Protocolos mínimos para inyección de dependencias en tests, sin afectar los tipos concretos. Swift 5.9 `any Protocol` con `@unchecked Sendable` en los mocks.
- **@Observable @MainActor:** macOS 14 requiere @MainActor en @Observable classes para propagar cambios a SwiftUI. Elimina data races en propiedades observadas sin overhead adicional.
- **checkStoredToken síncrono:** Cargar el token del Keychain en init() garantiza que `isAuthenticated` tiene el valor correcto antes del primer render de SwiftUI — evita el flash de LoginView al relanzar con sesión válida.

## Deviations from Plan

None - plan ejecutado exactamente como estaba escrito.

## Issues Encountered

None.

## User Setup Required

**Verificación manual requerida en Task 3 (checkpoint humano):**
- Firmar el proyecto con Apple ID en Xcode (Signing & Capabilities → Team)
- Ejecutar la app (Cmd+R) y verificar el flujo completo: login → ContentView → relanzar → ContentView (sesión persistida)
- Verificar que no hay errores de Keychain (OSStatus -25293 indicaría problema de firma)

Ver instrucciones completas en el checkpoint Task 3 del plan 03-03.

## Next Phase Readiness

- **Bloqueado:** Verificación end-to-end (Task 3 checkpoint) pendiente de aprobación humana
- Tras aprobación: Phase 4 (UI/UX principal) puede comenzar — AuthViewModel es la base de autenticación
- All 25 unit tests pasan (12 NetworkTests + 5 KeychainTests + 8 AuthViewModelTests)

---
*Phase: 03-swift-client-auth*
*Completed: 2026-03-03 (parcial — Task 3 pendiente)*

## Self-Check: PASSED

- FOUND: StrataClient/Auth/AuthViewModel.swift
- FOUND: StrataClientTests/AuthViewModelTests.swift
- FOUND: StrataClient/Auth/LoginView.swift
- FOUND: StrataClient/App/StrataApp.swift
- Commits verificados: 3be8f61, 67bf999
