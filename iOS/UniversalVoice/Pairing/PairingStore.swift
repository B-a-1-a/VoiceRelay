import Foundation
import Security
import UniversalVoiceProtocol

enum PairingStoreError: Error {
    case keychainStatus(OSStatus)
    case corrupt
}

/// Persists the single currently-paired Mac. Replace by re-scanning.
final class PairingStore: @unchecked Sendable {
    private let service = "dev.balashukla.voicerelay.app.pairing"
    private let account = "primary"

    func save(_ payload: PairingPayload) throws {
        let data = try JSONEncoder().encode(payload)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var combined = attributes
            combined[kSecValueData as String] = data
            combined[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(combined as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PairingStoreError.keychainStatus(addStatus)
            }
        default:
            throw PairingStoreError.keychainStatus(status)
        }
    }

    func load() throws -> PairingPayload? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = withUnsafeMutablePointer(to: &result) { ptr in
            SecItemCopyMatching(query as CFDictionary, ptr)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PairingStoreError.keychainStatus(status) }
        guard let data = result as? Data else { throw PairingStoreError.corrupt }
        return try JSONDecoder().decode(PairingPayload.self, from: data)
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PairingStoreError.keychainStatus(status)
        }
    }
}
