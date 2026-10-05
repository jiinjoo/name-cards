import Foundation
import Security

/// User preferences shared by the app. Values live in UserDefaults; the API key lives in the Keychain.
enum AppSettings {
    enum Key {
        static let defaultRegion = "defaultRegion"
        static let useClaude = "useClaude"
        static let addToEventGroup = "addToEventGroup"
        static let useCardAsPhoto = "useCardAsPhoto"
    }

    static var defaultRegion: String {
        UserDefaults.standard.string(forKey: Key.defaultRegion) ?? Locale.current.region?.identifier ?? "US"
    }

    static var useClaude: Bool { UserDefaults.standard.bool(forKey: Key.useClaude) }
}

/// Stores the Claude API key as a generic password in the login Keychain.
enum APIKeyStore {
    private static let service = "com.jiinjoo.namecards"
    private static let account = "anthropic-api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
