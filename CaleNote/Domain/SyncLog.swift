//
//  SyncLog.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import Foundation
import SwiftData

/// 同期ログレベル
enum SyncLogLevel: String, Codable {
    case info = "info"
    case warning = "warning"
    case error = "error"
}

/// 同期方向
enum SyncDirection: String, Codable {
    case upload = "upload"
    case download = "download"
    case bidirectional = "bidirectional"
}

/// 同期ログエントリー
@Model
final class SyncLog {
    /// 一意識別子
    var id: UUID

    /// 同期開始時刻
    var startAt: Date

    /// 同期完了時刻
    var endAt: Date?

    /// 同期方向
    var direction: SyncDirection

    /// ログレベル
    var level: SyncLogLevel

    /// 追加エントリー数
    var addedCount: Int

    /// 更新エントリー数
    var updatedCount: Int

    /// 削除エントリー数
    var deletedCount: Int

    /// エラーメッセージ
    var errorMessage: String?

    /// リトライ回数
    var retryCount: Int

    /// syncToken の使用状況
    var usedSyncToken: Bool

    /// API リクエスト回数
    var apiRequestCount: Int

    /// 同期タイプ（full/incremental）
    var syncType: String

    /// 所要時間（秒）
    var duration: TimeInterval {
        guard let end = endAt else { return 0 }
        return end.timeIntervalSince(startAt)
    }

    /// 成功したかどうか
    var isSuccess: Bool {
        level != .error
    }

    /// 処理した合計エントリー数
    var totalProcessedCount: Int {
        addedCount + updatedCount + deletedCount
    }

    /// 詳細説明
    var detailDescription: String {
        var parts: [String] = []

        // 同期タイプと方向
        parts.append("Type: \(syncType)")
        parts.append("Direction: \(direction.rawValue)")

        // 処理数
        if totalProcessedCount > 0 {
            parts.append("Processed: \(totalProcessedCount)")
            if addedCount > 0 {
                parts.append("Added: \(addedCount)")
            }
            if updatedCount > 0 {
                parts.append("Updated: \(updatedCount)")
            }
            if deletedCount > 0 {
                parts.append("Deleted: \(deletedCount)")
            }
        }

        // API リクエスト数
        if apiRequestCount > 0 {
            parts.append("API Requests: \(apiRequestCount)")
        }

        // syncToken
        if usedSyncToken {
            parts.append("syncToken: Used")
        } else {
            parts.append("syncToken: Not used (full sync)")
        }

        // 所要時間
        if let end = endAt {
            parts.append(String(format: "Duration: %.2fs", duration))
        }

        // リトライ
        if retryCount > 0 {
            parts.append("Retries: \(retryCount)")
        }

        // エラー
        if let error = errorMessage {
            parts.append("Error: \(error)")
        }

        return parts.joined(separator: "\n")
    }

    /// サマリー文字列
    var summaryDescription: String {
        if isSuccess {
            if totalProcessedCount > 0 {
                return "Processed \(totalProcessedCount) entries"
            } else {
                return "No changes"
            }
        } else {
            return errorMessage ?? "Unknown error"
        }
    }

    init(
        id: UUID = UUID(),
        startAt: Date,
        direction: SyncDirection,
        syncType: String = "incremental",
        usedSyncToken: Bool = true
    ) {
        self.id = id
        self.startAt = startAt
        self.direction = direction
        self.syncType = syncType
        self.usedSyncToken = usedSyncToken

        // デフォルト値
        self.level = .info
        self.addedCount = 0
        self.updatedCount = 0
        self.deletedCount = 0
        self.retryCount = 0
        self.apiRequestCount = 0
    }
}

// MARK: - Computed Properties for Display

extension SyncLog {
    /// 同期開始時刻のフォーマット文字列
    var startAtFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: startAt)
    }

    /// ステータスアイコン
    var statusIcon: String {
        switch level {
        case .info:
            return "✓"
        case .warning:
            return "⚠️"
        case .error:
            return "✕"
        }
    }

    /// ステータスカラー（SwiftUI Color の名前）
    var statusColorName: String {
        switch level {
        case .info:
            return "green"
        case .warning:
            return "orange"
        case .error:
            return "red"
        }
    }
}
