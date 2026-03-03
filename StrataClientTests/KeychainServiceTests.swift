import Testing
import Foundation
@testable import StrataClient

// NOTA: Estos tests usan el Keychain real del entorno de test (no mockeado).
// Security.framework no tiene mock oficial y el comportamiento real es lo que importa.
//
// AVISO IMPORTANTE: Si el test runner ejecuta con firma ad-hoc (sin signing identity
// "Apple Development"), los tests pueden fallar con errSecAuthFailed (-25293).
// Para evitarlo, asegurar que el target StrataClientTests tiene CODE_SIGN_IDENTITY
// = "Apple Development" y el mismo DEVELOPMENT_TEAM que StrataClient.
//
// Para ejecutar: xcodebuild test -project StrataClient.xcodeproj -scheme StrataClient
//   -destination 'platform=macOS' -only-testing:StrataClientTests/KeychainServiceTests

// MARK: - KeychainService Tests

@Suite("KeychainService")
struct KeychainServiceTests {
    // Usamos una key de test distinta para no interferir con datos reales
    // KeychainService usa service="com.strata.client", account="jwt-token"

    func makeService() -> KeychainService {
        return KeychainService()
    }

    @Test("saveToken guarda el JWT y loadToken devuelve el mismo String")
    func testSaveAndLoad() throws {
        let svc = makeService()
        let jwt = "header.payload.signature"

        // Limpiar estado previo
        try? svc.deleteToken()

        try svc.saveToken(jwt)
        let loaded = try svc.loadToken()
        #expect(loaded == jwt)

        // Cleanup
        try? svc.deleteToken()
    }

    @Test("saveToken segunda vez actualiza el item existente (upsert — no lanza errSecDuplicateItem)")
    func testSaveUpsert() throws {
        let svc = makeService()
        let first = "first.jwt.token"
        let second = "second.jwt.token"

        try? svc.deleteToken()

        try svc.saveToken(first)
        // Segunda llamada no debe lanzar
        try svc.saveToken(second)

        let loaded = try svc.loadToken()
        #expect(loaded == second)

        try? svc.deleteToken()
    }

    @Test("loadToken lanza KeychainError.itemNotFound si no hay token guardado")
    func testLoadNotFound() throws {
        let svc = makeService()
        try? svc.deleteToken()

        #expect(throws: KeychainService.KeychainError.itemNotFound) {
            _ = try svc.loadToken()
        }
    }

    @Test("deleteToken elimina el item del Keychain — loadToken posterior lanza itemNotFound")
    func testDeleteRemovesToken() throws {
        let svc = makeService()
        try? svc.deleteToken()

        try svc.saveToken("some.jwt")
        try svc.deleteToken()

        #expect(throws: KeychainService.KeychainError.itemNotFound) {
            _ = try svc.loadToken()
        }
    }

    @Test("deleteToken no lanza error si no hay item que eliminar")
    func testDeleteWhenNoToken() throws {
        let svc = makeService()
        try? svc.deleteToken()

        // No debe lanzar
        try svc.deleteToken()
    }
}
