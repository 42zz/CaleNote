//
//  CalendarSettings.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Foundation

/// カレンダー設定を管理するサービス
final class CalendarSettings {
    // MARK: - Singleton

    @MainActor static let shared = CalendarSettings()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let targetCalendarId = "targetCalendarId"
        static let syncWindowDaysPast = "syncWindowDaysPast"
        static let syncWindowDaysFuture = "syncWindowDaysFuture"
        static let calendarListSyncToken = "calendarListSyncToken"
        static let lastCalendarListSyncAt = "lastCalendarListSyncAt"
    }

    // MARK: - Properties

    private let defaults = UserDefaults.standard

    /// ターゲットカレンダーID（新規エントリを作成するカレンダー）
    var targetCalendarId: String {
        get {
            defaults.string(forKey: Keys.targetCalendarId) ?? "primary"
        }
        set {
            defaults.set(newValue, forKey: Keys.targetCalendarId)
        }
    }

    /// 同期ウィンドウ（過去）
    var syncWindowDaysPast: Int {
        get {
            let value = defaults.integer(forKey: Keys.syncWindowDaysPast)
            return value > 0 ? value : 30 // デフォルト: 30日前
        }
        set {
            defaults.set(newValue, forKey: Keys.syncWindowDaysPast)
        }
    }

    /// 同期ウィンドウ（未来）
    var syncWindowDaysFuture: Int {
        get {
            let value = defaults.integer(forKey: Keys.syncWindowDaysFuture)
            return value > 0 ? value : 90 // デフォルト: 90日先
        }
        set {
            defaults.set(newValue, forKey: Keys.syncWindowDaysFuture)
        }
    }

    /// カレンダーリストの同期トークン
    var calendarListSyncToken: String? {
        get {
            defaults.string(forKey: Keys.calendarListSyncToken)
        }
        set {
            defaults.set(newValue, forKey: Keys.calendarListSyncToken)
        }
    }

    /// 最終カレンダーリスト同期日時
    var lastCalendarListSyncAt: Date? {
        get {
            defaults.object(forKey: Keys.lastCalendarListSyncAt) as? Date
        }
        set {
            defaults.set(newValue, forKey: Keys.lastCalendarListSyncAt)
        }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Methods

    /// 設定をリセット
    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.targetCalendarId)
        defaults.removeObject(forKey: Keys.syncWindowDaysPast)
        defaults.removeObject(forKey: Keys.syncWindowDaysFuture)
        defaults.removeObject(forKey: Keys.calendarListSyncToken)
        defaults.removeObject(forKey: Keys.lastCalendarListSyncAt)
    }

    /// カレンダーリストの同期トークンをクリア
    func clearCalendarListSyncToken() {
        calendarListSyncToken = nil
    }
}

/// ゴミ箱設定を管理するサービス
final class TrashSettings {
    @MainActor static let shared = TrashSettings()

    enum RetentionOption: Int, CaseIterable, Identifiable {
        case days7 = 7
        case days30 = 30
        case days60 = 60

        var id: Int { rawValue }

        var label: String {
            "\(rawValue)日"
        }
    }

    private enum Keys {
        static let isEnabled = "trashEnabled"
        static let retentionDays = "trashRetentionDays"
        static let autoPurgeEnabled = "trashAutoPurgeEnabled"
    }

    private let defaults = UserDefaults.standard

    /// ゴミ箱の有効/無効（デフォルト: 有効）
    var isEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.isEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.isEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
        }
    }

    /// 保持期間（日数）
    var retentionDays: Int {
        get {
            let value = defaults.integer(forKey: Keys.retentionDays)
            let normalized = RetentionOption(rawValue: value)?.rawValue
            return normalized ?? RetentionOption.days30.rawValue
        }
        set {
            let normalized = RetentionOption(rawValue: newValue)?.rawValue ?? RetentionOption.days30.rawValue
            defaults.set(normalized, forKey: Keys.retentionDays)
        }
    }

    /// 自動削除の有効/無効
    var autoPurgeEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.autoPurgeEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.autoPurgeEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoPurgeEnabled)
        }
    }

    /// 有効な保持期間候補
    var retentionOptions: [RetentionOption] {
        RetentionOption.allCases
    }

    func expirationDate(for deletedAt: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: retentionDays, to: deletedAt) ?? deletedAt
    }

    func remainingDays(from deletedAt: Date, reference: Date = Date(), calendar: Calendar = .current) -> Int {
        let expiration = expirationDate(for: deletedAt, calendar: calendar)
        let components = calendar.dateComponents([.day], from: reference, to: expiration)
        return max(0, components.day ?? 0)
    }

    func isExpired(deletedAt: Date, reference: Date = Date(), calendar: Calendar = .current) -> Bool {
        expirationDate(for: deletedAt, calendar: calendar) <= reference
    }
}
