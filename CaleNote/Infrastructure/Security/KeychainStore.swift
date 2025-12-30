//
//  KeychainStore.swift
//  CaleNote
//
//  Created by Codex on 2025/12/30.
//

import Foundation
import OSLog
import Security

struct KeychainStore {
    private let service: String
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "KeychainStore")

    init(service: String) {
        self.service = service
    }

    @discardableResult
    func save(_ data: Data, for key: String) -> Bool {
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save keychain item (status: \(status))")
            return false
        }
        return true
    }

    func load(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            logger.error("Failed to load keychain item (status: \(status))")
            return nil
        }
        return result as? Data
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }
        logger.error("Failed to delete keychain item (status: \(status))")
        return false
    }
}
