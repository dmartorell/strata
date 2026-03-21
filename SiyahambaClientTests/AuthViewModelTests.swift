import Testing
import Foundation
@testable import SiyahambaClient

// MARK: - Helpers JWT

/// Genera un JWT con el campo `exp` especificado (sin firma — solo para tests).
/// Formato: base64url(header).base64url({"sub":"test","exp":N}).fakesig
private func makeJWT(expiresAt: Date, sub: String = "test") -> String {
    let header = #"{"alg":"HS256","typ":"JWT"}"#
    let exp = Int(expiresAt.timeIntervalSince1970)
    let payload = #"{"sub":"\#(sub)","exp":\#(exp)}"#

    func b64url(_ s: String) -> String {
        Data(s.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    return "\(b64url(header)).\(b64url(payload)).fakesig"
}

private let validToken   = makeJWT(expiresAt: Date().addingTimeInterval(30 * 24 * 3600))   // 30 días
private let expiredToken  = makeJWT(expiresAt: Date().addingTimeInterval(-3600))            // expiró hace 1h
private let nearExpiryToken = makeJWT(expiresAt: Date().addingTimeInterval(3 * 24 * 3600)) // 3 días (< 7)
private let renewedToken  = makeJWT(expiresAt: Date().addingTimeInterval(90 * 24 * 3600))  // 90 días tras renew

// MARK: - MockKeychainService

final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    var stored: String?
    var saveError: Error?
    var loadError: Error?
    var deleteError: Error?

    func saveToken(_ token: String) throws {
        if let e = saveError { throw e }
        stored = token
    }

    func loadToken() throws -> String {
        if let e = loadError { throw e }
        guard let t = stored else { throw KeychainService.KeychainError.itemNotFound }
        return t
    }

    func deleteToken() throws {
        if let e = deleteError { throw e }
        stored = nil
    }
}

// MARK: - MockAPIClient

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var loginResult: Result<String, Error> = .success(validToken)
    var renewResult: Result<String, Error> = .success(renewedToken)

    func login(password: String) async throws -> String {
        return try loginResult.get()
    }

    func renewToken(current: String) async throws -> String {
        return try renewResult.get()
    }
}

// MARK: - AuthViewModelTests

@Suite("AuthViewModel", .serialized)
struct AuthViewModelTests {

    // MARK: init — token válido en Keychain

    @Test("init con token válido: isAuthenticated = true, token != nil")
    func testInitWithValidToken() async throws {
        let keychain = MockKeychainService()
        keychain.stored = validToken
        let api = MockAPIClient()

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == true)
        #expect(token == validToken)
    }

    // MARK: init — sin token en Keychain

    @Test("init sin token: isAuthenticated = false, token = nil")
    func testInitWithoutToken() async throws {
        let keychain = MockKeychainService()
        keychain.loadError = KeychainService.KeychainError.itemNotFound
        let api = MockAPIClient()

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == false)
        #expect(token == nil)
    }

    // MARK: init — token expirado

    @Test("init con token expirado: isAuthenticated = false, token = nil, Keychain limpio")
    func testInitWithExpiredToken() async throws {
        let keychain = MockKeychainService()
        keychain.stored = expiredToken
        let api = MockAPIClient()

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == false)
        #expect(token == nil)
        #expect(keychain.stored == nil, "Keychain debe estar limpio tras detectar token expirado")
    }

    // MARK: init — token cerca de expirar (silentRenew)

    @Test("init con token < 7 días de vida: isAuthenticated = true, token renovado en Keychain")
    func testInitWithNearExpiryToken() async throws {
        let keychain = MockKeychainService()
        keychain.stored = nearExpiryToken
        let api = MockAPIClient()
        api.renewResult = .success(renewedToken)

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)

        // La renovación silenciosa es async (Task detached). Esperamos un momento.
        try await Task.sleep(nanoseconds: 200_000_000)

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == true)
        #expect(token == renewedToken, "El token debe haberse renovado silenciosamente")
        #expect(keychain.stored == renewedToken, "Keychain debe tener el token renovado")
    }

    // MARK: login — exitoso

    @Test("login exitoso: isAuthenticated = true, token guardado en Keychain")
    func testLoginSuccess() async throws {
        let keychain = MockKeychainService()
        keychain.loadError = KeychainService.KeychainError.itemNotFound
        let api = MockAPIClient()
        api.loginResult = .success(validToken)

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)
        try await vm.login(password: "correct")

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == true)
        #expect(token == validToken)
        #expect(keychain.stored == validToken)
    }

    // MARK: login — fallido

    @Test("login fallido: lanza el error tal cual")
    func testLoginFailure() async throws {
        let keychain = MockKeychainService()
        keychain.loadError = KeychainService.KeychainError.itemNotFound
        let api = MockAPIClient()
        api.loginResult = .failure(APIError.httpError(401))

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)

        await #expect(throws: APIError.httpError(401)) {
            try await vm.login(password: "wrong")
        }

        let isAuth = await vm.isAuthenticated
        #expect(isAuth == false)
    }

    // MARK: logout

    @Test("logout: isAuthenticated = false, token = nil, Keychain limpio")
    func testLogout() async throws {
        let keychain = MockKeychainService()
        keychain.stored = validToken
        let api = MockAPIClient()

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)
        await vm.logout()

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == false)
        #expect(token == nil)
        #expect(keychain.stored == nil)
    }

    // MARK: handleUnauthorized

    @Test("handleUnauthorized: equivalente a logout — isAuthenticated = false, token = nil")
    func testHandleUnauthorized() async throws {
        let keychain = MockKeychainService()
        keychain.stored = validToken
        let api = MockAPIClient()

        let vm = await AuthViewModel(keychain: keychain, apiClient: api)
        await vm.handleUnauthorized()

        let isAuth = await vm.isAuthenticated
        let token = await vm.token
        #expect(isAuth == false)
        #expect(token == nil)
        #expect(keychain.stored == nil)
    }
}
