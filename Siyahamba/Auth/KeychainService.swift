import Security
import Foundation

/// Wrapper de Security.framework para persistir el JWT de sesion en el Keychain del sistema.
///
/// Clave de almacenamiento:
///   - kSecClass: kSecClassGenericPassword
///   - kSecAttrService: "com.siyahamba.client"
///   - kSecAttrAccount: "jwt-token"
///   - kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (por defecto)
///     (accesible tras primer desbloqueo; no migra a otros dispositivos via iCloud Keychain)
///
/// El atributo `accessible` es configurable en el initializer para que los tests puedan
/// usar kSecAttrAccessibleAlways sin afectar a la configuracion de produccion.
final class KeychainService {

    // MARK: - Error

    enum KeychainError: Error, Equatable {
        /// El item no existe en el Keychain (errSecItemNotFound).
        case itemNotFound
        /// Los datos recuperados no son un String UTF-8 valido.
        case invalidFormat
        /// Cualquier otro OSStatus no esperado.
        case unexpectedStatus(OSStatus)
    }

    // MARK: - Private constants

    private let service: String
    private let account: String
    private let accessible: CFString

    // MARK: - Init

    /// - Parameters:
    ///   - service: Identificador de servicio del Keychain (default: "com.siyahamba.client").
    ///   - account: Nombre de cuenta del Keychain (default: "jwt-token").
    ///   - accessible: Politica de accesibilidad (default: AfterFirstUnlockThisDeviceOnly).
    ///     Los tests pueden pasar kSecAttrAccessibleAlways para operar sin firma Apple Development.
    init(
        service: String = "com.siyahamba.client",
        account: String = "jwt-token",
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.account = account
        self.accessible = accessible
    }

    // MARK: - Query base

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    // MARK: - Public API

    /// Guarda un JWT en el Keychain.
    ///
    /// Usa patron upsert: intenta añadir primero; si ya existe (errSecDuplicateItem), lo actualiza.
    /// - Parameter token: El JWT a persistir como String.
    /// - Throws: `KeychainError.unexpectedStatus` si ocurre un error de Keychain inesperado.
    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidFormat
        }

        // Intentar añadir directamente
        var addQuery = baseQuery
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = accessible

        var status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // El item ya existe — actualizarlo (upsert)
            let updateAttributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: accessible,
            ]
            status = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Recupera el JWT del Keychain.
    ///
    /// - Returns: El JWT guardado como String.
    /// - Throws: `KeychainError.itemNotFound` si no hay token guardado.
    ///           `KeychainError.invalidFormat` si los datos no son UTF-8.
    ///           `KeychainError.unexpectedStatus` para otros errores de Keychain.
    func loadToken() throws -> String {
        var loadQuery = baseQuery
        loadQuery[kSecReturnData] = true
        loadQuery[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(loadQuery as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidFormat
            }
            return token
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Elimina el JWT del Keychain.
    ///
    /// Es idempotente — no lanza si no hay item que eliminar.
    /// - Throws: `KeychainError.unexpectedStatus` si ocurre un error inesperado distinto a itemNotFound.
    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            // Item eliminado o ya no existia — ambos son exito
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
