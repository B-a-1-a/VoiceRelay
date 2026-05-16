import Foundation
import Security
import UniversalVoiceProtocol

enum PSKStoreError: Error {
    case keychainStatus(OSStatus)
    case missing
    case corrupt
}

/// Generates a 32-byte PSK on first launch and persists it in the macOS keychain.
final class PSKStore {
    private let service = "dev.balashukla.voicerelay.helper.psk"
    private let account = "default"

    func loadOrCreate() throws -> Data {
        if let existing = try load() { return existing }
        let psk = SessionCrypto.freshPSK()
        try save(psk)
        return psk
    }

    func deviceUUID() -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "deviceUUID") { return stored }
        let new = UUID().uuidString
        defaults.set(new, forKey: "deviceUUID")
        return new
    }

    func serviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }

    private func load() throws -> Data? {
        var query: [String: Any] = [
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
        guard status == errSecSuccess else { throw PSKStoreError.keychainStatus(status) }
        guard let data = result as? Data else { throw PSKStoreError.corrupt }
        _ = query
        return data
    }

    private func save(_ psk: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: psk,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PSKStoreError.keychainStatus(status) }
    }
}
