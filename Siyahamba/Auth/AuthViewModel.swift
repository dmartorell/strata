import Foundation
import Observation
import JWTDecode

// MARK: - Protocols para inyección de dependencias (testability)

protocol KeychainServiceProtocol: Sendable {
    func saveToken(_ token: String) throws
    func loadToken() throws -> String
    func deleteToken() throws
}

protocol APIClientProtocol: Sendable {
    func login(password: String) async throws -> String
    func renewToken(current: String) async throws -> String
}

protocol AuthTokenProviderProtocol: AnyObject {
    var token: String? { get }
}

// MARK: - Conformances de tipos concretos

extension KeychainService: KeychainServiceProtocol {}
extension APIClient: APIClientProtocol {}
extension AuthViewModel: AuthTokenProviderProtocol {}

// MARK: - AuthViewModel

@Observable
@MainActor
final class AuthViewModel {
    private(set) var isAuthenticated: Bool = false
    private(set) var token: String? = nil

    private let keychain: any KeychainServiceProtocol
    private let apiClient: any APIClientProtocol
    private var isRenewing: Bool = false

    init(keychain: any KeychainServiceProtocol = KeychainService(),
         apiClient: any APIClientProtocol = APIClient()) {
        self.keychain = keychain
        self.apiClient = apiClient
        checkStoredToken()
    }

    // MARK: - Public API

    func login(password: String) async throws {
        let jwt = try await apiClient.login(password: password)
        try keychain.saveToken(jwt)
        token = jwt
        isAuthenticated = true
    }

    func logout() {
        try? keychain.deleteToken()
        token = nil
        isAuthenticated = false
    }

    func handleUnauthorized() {
        logout()
    }

    // MARK: - Private

    private func checkStoredToken() {
        guard let stored = try? keychain.loadToken() else {
            return
        }

        if isExpired(stored) {
            try? keychain.deleteToken()
            return
        }

        token = stored
        isAuthenticated = true

        if needsRenewal(stored) {
            scheduleRenewalIfNeeded(for: stored)
        }
    }

    private func isExpired(_ token: String) -> Bool {
        guard let jwt = try? decode(jwt: token),
              let expiresAt = jwt.expiresAt else {
            return true
        }
        return expiresAt <= Date()
    }

    private func needsRenewal(_ token: String) -> Bool {
        guard let jwt = try? decode(jwt: token),
              let expiresAt = jwt.expiresAt else {
            return false
        }
        let sevenDays: TimeInterval = 7 * 24 * 3600
        return expiresAt.timeIntervalSinceNow < sevenDays
    }

    private func scheduleRenewalIfNeeded(for currentToken: String) {
        guard !isRenewing else { return }
        isRenewing = true
        Task {
            defer { Task { @MainActor in self.isRenewing = false } }
            try? await silentRenew(current: currentToken)
        }
    }

    private func silentRenew(current: String) async throws {
        let newToken = try await apiClient.renewToken(current: current)
        try keychain.saveToken(newToken)
        await MainActor.run {
            self.token = newToken
        }
    }
}
