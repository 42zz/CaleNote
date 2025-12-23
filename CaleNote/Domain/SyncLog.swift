//
//  SyncLog.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/22.
//
import Foundation
import SwiftData
import CryptoKit

@Model
final class SyncLog {
    @Attribute(.unique) var id: UUID
    var timestamp: Date  // 同期開始時刻
    var endTimestamp: Date?  // 同期終了時刻
    var syncType: String  // 同期種別: "incremental", "full", "archive", "journal_push"
    var calendarIdHash: String?  // カレンダーIDのSHA256ハッシュ（最初の8文字）
    var httpStatusCode: Int?
    var updatedCount: Int
    var deletedCount: Int
    var skippedCount: Int
    var conflictCount: Int
    var had410Fallback: Bool  // syncToken期限切れでフルバックした
    var had429Retry: Bool  // レート制限でリトライした
    var errorType: String?  // エラー種別
    var errorMessage: String?  // エラーメッセージ

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        endTimestamp: Date? = nil,
        syncType: String,
        calendarIdHash: String? = nil,
        httpStatusCode: Int? = nil,
        updatedCount: Int = 0,
        deletedCount: Int = 0,
        skippedCount: Int = 0,
        conflictCount: Int = 0,
        had410Fallback: Bool = false,
        had429Retry: Bool = false,
        errorType: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.syncType = syncType
        self.calendarIdHash = calendarIdHash
        self.httpStatusCode = httpStatusCode
        self.updatedCount = updatedCount
        self.deletedCount = deletedCount
        self.skippedCount = skippedCount
        self.conflictCount = conflictCount
        self.had410Fallback = had410Fallback
        self.had429Retry = had429Retry
        self.errorType = errorType
        self.errorMessage = errorMessage
    }

    // カレンダーIDからハッシュを生成
    static func hashCalendarId(_ calendarId: String) -> String {
        let data = Data(calendarId.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    // JSON形式でエクスポート
    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "id": id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "syncType": syncType,
            "updatedCount": updatedCount,
            "deletedCount": deletedCount,
            "skippedCount": skippedCount,
            "conflictCount": conflictCount,
            "had410Fallback": had410Fallback,
            "had429Retry": had429Retry
        ]

        if let endTimestamp = endTimestamp {
            json["endTimestamp"] = ISO8601DateFormatter().string(from: endTimestamp)
            json["durationSeconds"] = endTimestamp.timeIntervalSince(timestamp)
        }
        if let calendarIdHash = calendarIdHash {
            json["calendarIdHash"] = calendarIdHash
        }
        if let httpStatusCode = httpStatusCode {
            json["httpStatusCode"] = httpStatusCode
        }
        if let errorType = errorType {
            json["errorType"] = errorType
        }
        if let errorMessage = errorMessage {
            json["errorMessage"] = errorMessage
        }

        return json
    }
}
