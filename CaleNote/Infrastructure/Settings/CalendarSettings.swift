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

    static let shared = CalendarSettings()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let targetCalendarId = "targetCalendarId"
        static let syncWindowDaysPast = "syncWindowDaysPast"
        static let syncWindowDaysFuture = "syncWindowDaysFuture"
    }

    // MARK: - Properties

    private let defaults = UserDefaults.standard

    /// ターゲットカレンダーID
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

    // MARK: - Initialization

    private init() {}

    // MARK: - Methods

    /// 設定をリセット
    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.targetCalendarId)
        defaults.removeObject(forKey: Keys.syncWindowDaysPast)
        defaults.removeObject(forKey: Keys.syncWindowDaysFuture)
    }
}
