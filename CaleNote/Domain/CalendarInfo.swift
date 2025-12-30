//
//  CalendarInfo.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Foundation
import SwiftData

/// Google Calendarのカレンダー情報をローカルにキャッシュするモデル
///
/// GoogleカレンダーAPIから取得したカレンダーリストをローカルに保存し、
/// カレンダーの表示/非表示設定やカラー情報を管理する。
@Model
final class CalendarInfo {
    // MARK: - Properties

    /// カレンダーID（Google Calendar ID）
    @Attribute(.unique)
    var calendarId: String

    /// カレンダー名
    var summary: String

    /// カレンダーの説明
    var calendarDescription: String?

    /// 背景色（16進数カラーコード、例: "#FF6B6B"）
    var backgroundColor: String?

    /// 前景色（16進数カラーコード）
    var foregroundColor: String?

    /// アクセス権限（owner, writer, reader, freeBusyReader）
    var accessRole: String?

    /// プライマリカレンダーかどうか
    var isPrimary: Bool

    /// タイムラインに表示するかどうか
    var isVisible: Bool

    /// 同期対象かどうか
    var isSyncEnabled: Bool

    /// 最終更新日時
    var updatedAt: Date

    // MARK: - Initialization

    /// CalendarInfo の初期化
    /// - Parameters:
    ///   - calendarId: カレンダーID
    ///   - summary: カレンダー名
    ///   - calendarDescription: カレンダーの説明
    ///   - backgroundColor: 背景色
    ///   - foregroundColor: 前景色
    ///   - accessRole: アクセス権限
    ///   - isPrimary: プライマリカレンダーかどうか
    ///   - isVisible: タイムラインに表示するかどうか
    ///   - isSyncEnabled: 同期対象かどうか
    init(
        calendarId: String,
        summary: String,
        calendarDescription: String? = nil,
        backgroundColor: String? = nil,
        foregroundColor: String? = nil,
        accessRole: String? = nil,
        isPrimary: Bool = false,
        isVisible: Bool = true,
        isSyncEnabled: Bool = true
    ) {
        self.calendarId = calendarId
        self.summary = summary
        self.calendarDescription = calendarDescription
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.accessRole = accessRole
        self.isPrimary = isPrimary
        self.isVisible = isVisible
        self.isSyncEnabled = isSyncEnabled
        self.updatedAt = Date()
    }
}

// MARK: - Access Role

extension CalendarInfo {
    /// アクセス権限の種類
    enum AccessRole: String {
        case owner = "owner"
        case writer = "writer"
        case reader = "reader"
        case freeBusyReader = "freeBusyReader"
    }

    /// 書き込み可能かどうか
    var isWritable: Bool {
        guard let role = accessRole else { return false }
        return role == AccessRole.owner.rawValue || role == AccessRole.writer.rawValue
    }

    /// 読み取り専用かどうか
    var isReadOnly: Bool {
        !isWritable
    }
}

// MARK: - Helper Methods

extension CalendarInfo {
    /// Google CalendarListEntryからCalendarInfoを作成
    /// - Parameter entry: Google Calendar API のカレンダーエントリ
    /// - Returns: CalendarInfo インスタンス
    static func from(_ entry: CalendarListEntry) -> CalendarInfo {
        CalendarInfo(
            calendarId: entry.id,
            summary: entry.summary ?? "Untitled Calendar",
            calendarDescription: entry.description,
            backgroundColor: entry.backgroundColor,
            foregroundColor: entry.foregroundColor,
            accessRole: entry.accessRole,
            isPrimary: entry.primary ?? false,
            isVisible: entry.selected ?? true,
            isSyncEnabled: true
        )
    }

    /// Google CalendarListEntryから情報を更新
    /// - Parameter entry: Google Calendar API のカレンダーエントリ
    func update(from entry: CalendarListEntry) {
        summary = entry.summary ?? "Untitled Calendar"
        calendarDescription = entry.description
        backgroundColor = entry.backgroundColor
        foregroundColor = entry.foregroundColor
        accessRole = entry.accessRole
        isPrimary = entry.primary ?? false
        // isVisible と isSyncEnabled はユーザー設定なので更新しない
        updatedAt = Date()
    }

    /// 表示/非表示を切り替え
    func toggleVisibility() {
        isVisible.toggle()
        updatedAt = Date()
    }

    /// 同期設定を切り替え
    func toggleSync() {
        isSyncEnabled.toggle()
        updatedAt = Date()
    }
}
