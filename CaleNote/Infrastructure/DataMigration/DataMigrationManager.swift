//
//  DataMigrationManager.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import Foundation
import SwiftData
import OSLog

/// SwiftData スキーママイグレーションを管理するサービス
@MainActor
final class DataMigrationManager {
    // MARK: - Singleton

    static let shared = DataMigrationManager()

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "DataMigration")

    // MARK: - Initialization

    private init() {}

    // MARK: - Migration Strategy

    /// SwiftData コンテナの設定を生成
    /// - Parameters:
    ///   - modelContainer: 既存のモデルコンテナ（ある場合）
    ///   - inMemory: インメモリモード（テスト用）
    /// - Returns: ModelContainerConfiguration
    func createConfiguration(
        inMemory: Bool = false
    ) -> ModelConfiguration {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            // アプリケーションサポートディレクトリに保存
            let URL = applicationSupportDirectory
                .appendingPathComponent("CaleNote.store")

            // VersionedSchemaのモデルリストを使用
            let schema = Schema(CurrentSchema.models)
            configuration = ModelConfiguration(
                schema: schema,
                url: URL
            )
        }

        logger.info("Created ModelConfiguration: \(inMemory ? "in-memory" : "persistent")")
        return configuration
    }

    /// マイグレーションが必要かどうかをチェック
    /// - Parameter context: ModelContext
    /// - Returns: マイグレーションが必要かどうか
    func needsMigration(using context: ModelContext) -> Bool {
        // SwiftData は自動的にスキーマの不一致を検出する
        // このメソッドは将来的な拡張用に予約
        return false
    }

    /// データのバックアップを作成
    /// - Parameter context: ModelContext
    /// - Returns: バックアップURL（成功時）、nil（失敗時）
    func createBackup(using context: ModelContext) async throws -> URL? {
        let backupURL = applicationSupportDirectory
            .appendingPathComponent("Backups")
            .appendingPathComponent("CaleNote_\(Date().timeIntervalSince1970).store")

        // バックアップディレクトリの作成
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 現在のストアファイルをコピー
        let storeURL = applicationSupportDirectory.appendingPathComponent("CaleNote.store")

        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.copyItem(at: storeURL, to: backupURL)
            logger.info("Backup created at: \(backupURL.path)")
            return backupURL
        }

        return nil
    }

    /// マイグレーション前の準備
    /// - Parameter context: ModelContext
    func prepareForMigration(using context: ModelContext) async throws {
        logger.info("Preparing for migration...")

        // 1. バックアップ作成
        if let backupURL = try await createBackup(using: context) {
            logger.info("Backup created at: \(backupURL.path)")
        }

        // 2. 既存のデータをエクスポート（将来的な実装）
        // try await exportDataForMigration(using: context)

        logger.info("Migration preparation completed")
    }

    /// マイグレーション後のクリーンアップ
    /// - Parameter context: ModelContext
    func cleanupAfterMigration(using context: ModelContext) async throws {
        logger.info("Cleaning up after migration...")

        // 1. 古いバックアップの削除（直近5個を除く）
        try cleanupOldBackups(keepRecent: 5)

        // 2. インデックスの再構築
        // await rebuildIndexes(using: context)

        logger.info("Post-migration cleanup completed")
    }

    // MARK: - Helper Methods

    /// アプリケーションサポートディレクトリ
    private var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
    }

    /// 古いバックアップを削除
    /// - Parameter keepRecent: 残す最新のバックアップ数
    private func cleanupOldBackups(keepRecent: Int) throws {
        let backupsDirectory = applicationSupportDirectory
            .appendingPathComponent("Backups")

        guard FileManager.default.fileExists(atPath: backupsDirectory.path) else {
            return
        }

        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )

        // 変更日時でソート
        let sortedURLs = backupURLs.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 > date2
        }

        // 古いバックアップを削除
        let urlsToDelete = sortedURLs.dropFirst(keepRecent)
        for url in urlsToDelete {
            try FileManager.default.removeItem(at: url)
            logger.info("Deleted old backup: \(url.lastPathComponent)")
        }
    }
}

// MARK: - Migration Plan

/// SwiftData マイグレーションプラン
///
/// 将来的にスキーマバージョンが追加されたら、`stages`に移行ステージを追加
///
/// 使用例:
/// ```swift
/// enum CaleNoteMigrationPlan: SchemaMigrationPlan {
///     static var schemas: [any VersionedSchema.Type] {
///         [CaleNoteSchemaV1.self, CaleNoteSchemaV2.self]
///     }
///
///     static var stages: [MigrationStage] {
///         [migrateV1toV2]
///     }
/// }
///
/// let migrateV1toV2 = MigrationStage(
///     from: CaleNoteSchemaV1.self,
///     to: CaleNoteSchemaV2.self,
///     willMigrate: { context in
///         // マイグレーション前の準備
///     },
///     didMigrate: { context in
///         // マイグレーション後の処理
///     }
/// )
/// ```
enum CaleNoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CaleNoteSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // 現時点ではマイグレーションステージなし（V1のみ）
        // 将来的にスキーマV2などが追加されたらここにステージを定義
        []
    }
}

// MARK: - Migration Stage Extensions

extension SchemaMigrationPlan {
    /// 次のスキーマバージョンに移行する準備ができているか
    static var canMigrate: Bool {
        !Self.stages.isEmpty
    }

    /// 現在のスキーマバージョン
    static var currentVersion: String {
        "\(Self.schemas.last?.versionIdentifier ?? Schema.Version(0, 0, 0))"
    }
}
