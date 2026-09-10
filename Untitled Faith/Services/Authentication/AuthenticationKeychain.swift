import Foundation
import Security

struct AuthenticationKeychain {
    var service = "com.lukefournier.UntitledFaith.authentication"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "session",
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> StoredAuthentication? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AuthenticationError.keychain }
        guard let stored = try? JSONDecoder().decode(StoredAuthentication.self, from: data) else {
            try clear()
            return nil
        }
        return stored
    }

    func save(_ authentication: StoredAuthentication) throws {
        let data = try JSONEncoder().encode(authentication)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AuthenticationError.keychain }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthenticationError.keychain }
    }
}
