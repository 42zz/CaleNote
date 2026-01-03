//
//  SyncLogger.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import Foundation
import SwiftData
import OSLog
import Combine

/// 同期ロガーサービス
@MainActor
final class SyncLogger: ObservableObject {
    // MARK: - Singleton

    static let shared = SyncLogger()

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "SyncLogger")

    // MARK: - Configuration

    /// 最大保持件数
    private let maxLogCount = 100

    /// ModelContext
    private var modelContext: ModelContext?

    // MARK: - Properties

    /// 現在進行中の同期ログ
    @Published private(set) var currentLog: SyncLog?

    /// すべての同期ログ（新しい順）
    @Published private(set) var allLogs: [SyncLog] = []

    // MARK: - Initialization

    private init() {}

    // MARK: - Setup

    /// ModelContext を設定
    func configure(with context: ModelContext) {
        self.modelContext = context
        loadLogs()
    }

    /// 保存されているログを読み込み
    private func loadLogs() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<SyncLog>(sortBy: [SortDescriptor(\.startAt, order: .reverse)])
        do {
            self.allLogs = try context.fetch(descriptor)
            logger.info("Loaded \(self.allLogs.count) sync logs")
        } catch {
            logger.error("Failed to load sync logs: \(error)")
        }
    }

    // MARK: - Logging Lifecycle

    /// 同期ログを開始
    /// - Parameters:
    ///   - direction: 同期方向
    ///   - syncType: 同期タイプ（full/incremental）
    ///   - usedSyncToken: syncToken を使用したか
    /// - Returns: 作成された SyncLog
    @discardableResult
    func startSync(
        direction: SyncDirection,
        syncType: String = "incremental",
        usedSyncToken: Bool = true
    ) -> SyncLog {
        let log = SyncLog(
            startAt: Date(),
            direction: direction,
            syncType: syncType,
            usedSyncToken: usedSyncToken
        )

        currentLog = log

        guard let context = modelContext else {
            logger.warning("ModelContext not configured, log not persisted")
            return log
        }

        context.insert(log)
        try? context.save()

        logger.info("Started sync: \(direction.rawValue) (\(syncType))")

        return log
    }

    /// 同期ログを完了
    /// - Parameters:
    ///   - addedCount: 追加エントリー数
    ///   - updatedCount: 更新エントリー数
    ///   - deletedCount: 削除エントリー数
    ///   - apiRequestCount: API リクエスト数
    ///   - level: ログレベル
    func completeSync(
        addedCount: Int = 0,
        updatedCount: Int = 0,
        deletedCount: Int = 0,
        apiRequestCount: Int = 0,
        level: SyncLogLevel = .info
    ) {
        guard let log = currentLog else {
            logger.warning("No current sync log to complete")
            return
        }

        log.endAt = Date()
        log.addedCount = addedCount
        log.updatedCount = updatedCount
        log.deletedCount = deletedCount
        log.apiRequestCount = apiRequestCount
        log.level = level

        save()

        logger.info("""
            Completed sync: \(log.direction.rawValue) \
            (Added: \(addedCount), Updated: \(updatedCount), Deleted: \(deletedCount), \
            API Requests: \(apiRequestCount), Duration: \(String(format: "%.2fs", log.duration)))
            """)

        currentLog = nil
    }

    /// 同期ログをエラー状態で完了
    /// - Parameters:
    ///   - error: エラーメッセージ
    ///   - retryCount: リトライ回数
    func failSync(error: String, retryCount: Int = 0) {
        guard let log = currentLog else {
            logger.warning("No current sync log to fail")
            return
        }

        log.endAt = Date()
        log.errorMessage = error
        log.retryCount = retryCount
        log.level = .error

        save()

        logger.error("Sync failed: \(error) (Retries: \(retryCount))")

        currentLog = nil
    }

    /// ログを保存
    private func save() {
        guard let context = modelContext else { return }

        do {
            try context.save()
            loadLogs()
            cleanupOldLogs()
        } catch {
            logger.error("Failed to save sync log: \(error)")
        }
    }

    // MARK: - Log Management

    /// 古いログを削除（最大保持件数を維持）
    private func cleanupOldLogs() {
        guard let context = modelContext else { return }

        if allLogs.count > maxLogCount {
            let logsToDelete = allLogs[maxLogCount...]

            for log in logsToDelete {
                context.delete(log)
            }

            do {
                try context.save()
                logger.info("Deleted \(logsToDelete.count) old sync logs")
            } catch {
                logger.error("Failed to delete old logs: \(error)")
            }
        }
    }

    /// すべてのログを削除
    func clearAllLogs() {
        guard let context = modelContext else { return }

        for log in self.allLogs {
            context.delete(log)
        }

        do {
            try context.save()
            self.allLogs = []
            logger.info("Cleared all sync logs")
        } catch {
            logger.error("Failed to clear logs: \(error)")
        }
    }

    // MARK: - Export

    /// ログをテキストファイルとしてエクスポート
    func exportLogs() -> URL? {
        let text = generateExportText()

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "CaleNote_SyncLogs_\(Date().timeIntervalSince1970).txt"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.info("Exported sync logs to: \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Failed to export logs: \(error)")
            return nil
        }
    }

    /// エクスポート用テキストを生成
    private func generateExportText() -> String {
        var lines: [String] = []

        lines.append("CaleNote Sync Logs")
        lines.append("Generated: \(Date())")
        lines.append("Total Logs: \(allLogs.count)")
        lines.append(String(repeating: "=", count: 80))
        lines.append("")

        for (index, log) in allLogs.enumerated() {
            lines.append("## Log #\(allLogs.count - index)")
            lines.append("")

            lines.append("Status: \(log.level.rawValue.uppercased()) \(log.statusIcon)")
            lines.append("Started: \(log.startAtFormatted)")
            if let end = log.endAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .medium
                formatter.locale = Locale(identifier: "ja_JP")
                lines.append("Ended: \(formatter.string(from: end))")
            }
            lines.append("Duration: \(String(format: "%.2f", log.duration))s")
            lines.append("Direction: \(log.direction.rawValue)")
            lines.append("Type: \(log.syncType)")

            if log.totalProcessedCount > 0 {
                lines.append("")
                lines.append("Processed Entries:")
                lines.append("  Added: \(log.addedCount)")
                lines.append("  Updated: \(log.updatedCount)")
                lines.append("  Deleted: \(log.deletedCount)")
                lines.append("  Total: \(log.totalProcessedCount)")
            }

            if log.apiRequestCount > 0 {
                lines.append("API Requests: \(log.apiRequestCount)")
            }

            lines.append("syncToken: \(log.usedSyncToken ? "Used" : "Not used")")

            if log.retryCount > 0 {
                lines.append("Retries: \(log.retryCount)")
            }

            if let error = log.errorMessage {
                lines.append("")
                lines.append("Error:")
                lines.append("  \(error)")
            }

            lines.append("")
            lines.append(String(repeating: "-", count: 80))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Statistics

    /// 最近の同期統計
    struct SyncStatistics {
        var lastSyncAt: Date?
        var lastSuccessAt: Date?
        var pendingCount: Int = 0
        var failedCount: Int = 0
        var averageDuration: TimeInterval = 0
        var totalApiRequests: Int = 0
    }

    /// 同期統計を計算
    func calculateStatistics() -> SyncStatistics {
        var stats = SyncStatistics()

        guard !allLogs.isEmpty else {
            return stats
        }

        // 最終同期時刻
        stats.lastSyncAt = allLogs.first?.startAt

        // 最終成功時刻
        stats.lastSuccessAt = allLogs.first(where: { $0.isSuccess })?.startAt

        // 失敗・保留中のカウント
        stats.failedCount = allLogs.filter { $0.level == .error }.count
        stats.pendingCount = allLogs.filter { $0.level == .warning }.count

        // 平均所要時間（成功した同期のみ）
        let successfulLogs = allLogs.filter { $0.isSuccess && $0.endAt != nil }
        if !successfulLogs.isEmpty {
            let totalDuration = successfulLogs.reduce(0.0) { $0 + $1.duration }
            stats.averageDuration = totalDuration / Double(successfulLogs.count)
        }

        // 総 API リクエスト数
        stats.totalApiRequests = allLogs.reduce(0) { $0 + $1.apiRequestCount }

        return stats
    }
}
