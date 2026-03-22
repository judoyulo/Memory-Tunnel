import Foundation
import Security

/// Persists the JWT in the iOS Keychain.
final class TokenStore {
    static let shared = TokenStore()
    private init() {}

    private let service = "com.memorytunnel.app"
    private let account = "jwt"

    var token: String? {
        get { load() }
        set {
            if let value = newValue { save(value) }
            else                    { delete() }
        }
    }

    var isAuthenticated: Bool { token != nil }

    // MARK: - Keychain helpers

    private func save(_ value: String) {
        let data = Data(value.utf8)
        delete()
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
