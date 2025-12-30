//
//  SyncTokenStore.swift
//  CaleNote
//
//  Created by Codex on 2025/12/30.
//

import Foundation

final class SyncTokenStore {
    private let keychain = KeychainStore(service: "com.calenote.sync")
    private let storageKey = "calendar_sync_tokens"

    func load() -> [String: String] {
        guard let data = keychain.load(storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func save(_ tokens: [String: String]) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        _ = keychain.save(data, for: storageKey)
    }

    func clear() {
        _ = keychain.delete(storageKey)
    }
}
