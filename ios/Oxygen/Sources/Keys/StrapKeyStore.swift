// Adapted from ios/OpenCircuit/Helio/HelioKeyStore.swift at upstream 63e2796d323cea42d4835cf364bd0a4ebfa99682.
import Foundation
import Security

protocol StrapKeyStoring {
    func load() throws -> StrapAuthKey?
    func save(_ key: StrapAuthKey) throws
    func markRejected() throws
    func isRejected() throws -> Bool
}

enum StrapKeyStoreError: Error, Equatable {
    case keychainStatus(Int32)
}

struct StrapKeyStore: StrapKeyStoring {
    static let productionService = "com.emanuelefalli.oxygen.strap-auth-key"

    private static let keyAccount = "auth-key"
    private static let rejectedAccount = "auth-key-rejected"
    private static let rejectedMarker = Data([0x01])

    let service: String

    func load() throws -> StrapAuthKey? {
        guard let data = try read(account: Self.keyAccount) else { return nil }
        return StrapAuthKey(bytes: data)
    }

    func save(_ key: StrapAuthKey) throws {
        try write(key.bytes, account: Self.keyAccount)
        try remove(account: Self.rejectedAccount)
    }

    func markRejected() throws {
        try write(Self.rejectedMarker, account: Self.rejectedAccount)
    }

    func isRejected() throws -> Bool {
        try read(account: Self.rejectedAccount) != nil
    }

    func delete() throws {
        try remove(account: Self.keyAccount)
        try remove(account: Self.rejectedAccount)
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read(account: String) throws -> Data? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StrapKeyStoreError.keychainStatus(status) }
        return result as? Data
    }

    private func write(_ data: Data, account: String) throws {
        try remove(account: account)
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw StrapKeyStoreError.keychainStatus(status) }
    }

    private func remove(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StrapKeyStoreError.keychainStatus(status)
        }
    }
}
