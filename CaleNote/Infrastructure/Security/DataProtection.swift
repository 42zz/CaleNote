//
//  DataProtection.swift
//  CaleNote
//
//  Created by Codex on 2025/12/30.
//

import Foundation
import OSLog

enum DataProtection {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "DataProtection")

    static func protectedStoreURL(filename: String) throws -> URL {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "DataProtection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Application Support directory not found"]) 
        }

        let storeDirectory = appSupport.appendingPathComponent("CaleNote", isDirectory: true)
        if !fileManager.fileExists(atPath: storeDirectory.path) {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }

        applyFileProtection(to: storeDirectory)

        return storeDirectory.appendingPathComponent(filename)
    }

    static func applyFileProtection(to url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        } catch {
            logger.error("Failed to set file protection for \(url.path, privacy: .private): \(error.localizedDescription)")
        }
    }
}
