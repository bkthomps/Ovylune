import CryptoKit
import Foundation
import Security

/// Encrypts every value before it reaches SwiftData. The AES key is stored in
/// the device Keychain and is never written to the model store.
enum EncryptedField {
    private static let key = loadOrCreateKey()
    private static let keyService = "bkthomps.ovylune.swiftdata-encryption"
    private static let keyAccount = "primary-aes-gcm-key"

    static func seal<Value: Encodable>(_ value: Value) -> Data {
        do {
            let plaintext = try JSONEncoder().encode(value)
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                fatalError("AES-GCM did not produce a combined sealed box")
            }
            return combined
        } catch {
            fatalError("Could not encrypt a SwiftData field: \(error)")
        }
    }

    static func open<Value: Decodable>(_ type: Value.Type, from ciphertext: Data) -> Value {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode(type, from: plaintext)
        } catch {
            fatalError("Could not decrypt a SwiftData field: \(error)")
        }
    }

    private static func loadOrCreateKey() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        if readStatus == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        guard readStatus == errSecItemNotFound else {
            fatalError("Could not read the SwiftData encryption key (OSStatus \(readStatus))")
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return newKey
        }

        // Another thread or process may have created the key after our read.
        if addStatus == errSecDuplicateItem {
            var duplicateResult: CFTypeRef?
            let duplicateStatus = SecItemCopyMatching(query as CFDictionary, &duplicateResult)
            if duplicateStatus == errSecSuccess, let duplicateData = duplicateResult as? Data {
                return SymmetricKey(data: duplicateData)
            }
        }
        fatalError("Could not save the SwiftData encryption key (OSStatus \(addStatus))")
    }
}
