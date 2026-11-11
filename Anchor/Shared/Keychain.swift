import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Items are bound to this device
/// and available after the first unlock following boot.
enum Keychain {
    static let service = "app.anchor.Anchor"

    enum Account: String {
        case journalKey = "journal-encryption-key"
        case apiBibleKey = "api-bible-key"
        case claudeKey = "anthropic-api-key"
    }

    static func data(_ account: Account) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func set(_ data: Data?, for account: Account) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        guard let data else { return true }
        var query = base(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func string(_ account: Account) -> String? {
        data(account).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func setString(_ value: String?, for account: Account) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        set((trimmed?.isEmpty ?? true) ? nil : Data(trimmed!.utf8), for: account)
    }

    private static func base(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}
