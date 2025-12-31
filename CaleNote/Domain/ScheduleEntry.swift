//
//  ScheduleEntry.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation
import SwiftData

/// スケジュールエントリーの最小データ単位
///
/// CaleNoteにおける最小データ単位。ユーザー体験上は単一の概念として扱い、
/// 予定か記録かといった種別をユーザーに認識させない。
/// すべてのスケジュールエントリーは、Googleカレンダー上のイベントと1対1に対応する。
@Model
final class ScheduleEntry {
    // MARK: - Properties

    /// データソース（google / calenote）
    var source: String

    /// CaleNote管理フラグ
    var managedByCaleNote: Bool

    /// Google Calendar イベントID
    var googleEventId: String?

    /// Google Calendar ID（どのカレンダーに属するか）
    var calendarId: String?

    /// 開始日時
    var startAt: Date

    /// 終了日時
    var endAt: Date

    /// 全日イベントフラグ
    var isAllDay: Bool

    /// タイトル
    var title: String

    /// 本文（任意）
    var body: String?

    /// タグ配列
    var tags: [String]

    /// 同期状態（synced / pending / failed）
    var syncStatus: String

    /// 最終同期日時
    var lastSyncedAt: Date?

    /// 作成日時
    var createdAt: Date

    /// 更新日時
    var updatedAt: Date

    // MARK: - Initialization

    /// ScheduleEntry の初期化
    /// - Parameters:
    ///   - source: データソース（"google" または "calenote"）
    ///   - managedByCaleNote: CaleNote管理フラグ
    ///   - googleEventId: Google Calendar イベントID
    ///   - calendarId: Google Calendar ID
    ///   - startAt: 開始日時
    ///   - endAt: 終了日時
    ///   - isAllDay: 全日イベントフラグ（デフォルト: false）
    ///   - title: タイトル
    ///   - body: 本文（オプション）
    ///   - tags: タグ配列
    ///   - syncStatus: 同期状態（デフォルト: "pending"）
    ///   - lastSyncedAt: 最終同期日時（オプション）
    init(
        source: String,
        managedByCaleNote: Bool,
        googleEventId: String? = nil,
        calendarId: String? = nil,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool = false,
        title: String,
        body: String? = nil,
        tags: [String] = [],
        syncStatus: String = SyncStatus.pending.rawValue,
        lastSyncedAt: Date? = nil
    ) {
        self.source = source
        self.managedByCaleNote = managedByCaleNote
        self.googleEventId = googleEventId
        self.calendarId = calendarId
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.title = title
        self.body = body
        self.tags = tags
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Enums

/// データソース定義
extension ScheduleEntry {
    enum Source: String {
        case google = "google"
        case calenote = "calenote"
    }
}

/// 同期状態定義
extension ScheduleEntry {
    enum SyncStatus: String {
        case synced = "synced"
        case pending = "pending"
        case failed = "failed"
    }
}

// MARK: - Computed Properties

extension ScheduleEntry {
    /// 同期済みかどうか
    var isSynced: Bool {
        syncStatus == SyncStatus.synced.rawValue
    }

    /// 同期待ちかどうか
    var isPending: Bool {
        syncStatus == SyncStatus.pending.rawValue
    }

    /// 同期失敗かどうか
    var isFailed: Bool {
        syncStatus == SyncStatus.failed.rawValue
    }

    /// Google Calendar由来のエントリーかどうか
    var isFromGoogle: Bool {
        source == Source.google.rawValue
    }

    /// CaleNote作成のエントリーかどうか
    var isFromCaleNote: Bool {
        source == Source.calenote.rawValue
    }

    /// エントリーの長さ（秒）
    var duration: TimeInterval {
        endAt.timeIntervalSince(startAt)
    }
}

// MARK: - Validation

extension ScheduleEntry {
    enum ValidationError: Error, Equatable {
        case emptyTitle
        case invalidSource(String)
        case endBeforeStart
    }

    /// エントリーの整合性を検証
    func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errors.append(.emptyTitle)
        }

        if source != Source.google.rawValue && source != Source.calenote.rawValue {
            errors.append(.invalidSource(source))
        }

        if endAt < startAt {
            errors.append(.endBeforeStart)
        }

        return errors
    }
}

// MARK: - Helper Methods

extension ScheduleEntry {
    /// 同期状態を更新
    /// - Parameter status: 新しい同期状態
    func updateSyncStatus(_ status: SyncStatus) {
        syncStatus = status.rawValue
        if status == .synced {
            lastSyncedAt = Date()
        }
        updatedAt = Date()
    }

    /// タグを追加
    /// - Parameter tag: 追加するタグ
    func addTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        updatedAt = Date()
    }

    /// タグを削除
    /// - Parameter tag: 削除するタグ
    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        updatedAt = Date()
    }
}

// MARK: - All-day Helpers

extension ScheduleEntry {
    /// 全日イベントの表示/同期用に開始日と終了日（排他的）を整形
    func allDaySpan(using calendar: Calendar = .current) -> (startDay: Date, endDayExclusive: Date, dayCount: Int) {
        let startDay = calendar.startOfDay(for: startAt)
        var endDay = calendar.startOfDay(for: endAt)
        if endDay <= startDay {
            endDay = calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
        }
        let rawDayCount = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        let dayCount = max(1, rawDayCount)
        return (startDay, endDay, dayCount)
    }

    /// 複数日にまたがる全日イベントかどうか
    var isMultiDayAllDay: Bool {
        guard isAllDay else { return false }
        return allDaySpan().dayCount > 1
    }
}
