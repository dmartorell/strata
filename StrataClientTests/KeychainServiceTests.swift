import Testing
import Foundation
import Security
@testable import StrataClient

// NOTA: Estos tests usan el Keychain real del entorno de test (no mockeado).
// Security.framework no tiene mock oficial y el comportamiento real es lo que importa.
//
// ENTORNO DE TEST: Se usa kSecAttrAccessibleAlways (deprecated pero funcional en macOS tests)
// para que los tests funcionen con firma ad-hoc sin necesidad de DEVELOPMENT_TEAM configurado.
// La app en produccion usa kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly via el initializer
// sin argumentos de KeychainService.
//
// AVISO: Si los tests fallan con errSecAuthFailed (-25293) o errSecNoSuchKeychain (-25300),
// verificar que el proceso de test tiene acceso al login.keychain-db del usuario.

// MARK: - KeychainService Tests

// .serialized: los tests de Keychain no son seguros para ejecucion paralela
// porque comparten el mismo slot service/account en el Keychain del sistema.
@Suite("KeychainService", .serialized)
struct KeychainServiceTests {

    // Service/account unicos para tests — no interfieren con datos reales de la app
    let testService = "com.strata.client.tests"
    let testAccount = "jwt-token-test"

    func makeService() -> KeychainService {
        // kSecAttrAccessibleAlways: permite acceso sin restriccion de desbloqueo.
        // Usamos esto en tests para evitar el requisito de firma Apple Development
        // que kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly impone en macOS.
        return KeychainService(
            service: testService,
            account: testAccount,
            accessible: kSecAttrAccessibleAlways
        )
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
