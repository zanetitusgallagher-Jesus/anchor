import CryptoKit
import Foundation

/// Encrypts personal data at rest with AES-256-GCM. The 256-bit key is
/// generated on first use and kept only in the Keychain (this device only).
/// Losing the Keychain item means losing the journal, by design; exports
/// (Markdown/PDF) are the backup path.
enum JournalCrypto {
    enum CryptoError: Error { case keychainUnavailable, sealFailed }

    private static var cachedKey: SymmetricKey?

    static func key() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        if let data = Keychain.data(.journalKey), data.count == 32 {
            let k = SymmetricKey(data: data)
            cachedKey = k
            return k
        }
        let k = SymmetricKey(size: .bits256)
        let raw = k.withUnsafeBytes { Data($0) }
        guard Keychain.set(raw, for: .journalKey) else { throw CryptoError.keychainUnavailable }
        cachedKey = k
        return k
    }

    static func seal(_ data: Data) throws -> Data {
        try seal(data, key: key())
    }

    static func open(_ data: Data) throws -> Data {
        try open(data, key: key())
    }

    static func seal(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw CryptoError.sealFailed }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }

    static func seal<T: Encodable>(json value: T) throws -> Data {
        try seal(JSONEncoder().encode(value))
    }

    static func open<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: open(data))
    }
}
