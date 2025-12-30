//
//  CalendarListService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import Foundation
import OSLog
import SwiftData

/// カレンダーリストを管理するサービス
///
/// Google Calendar APIからカレンダーリストを取得し、ローカルにキャッシュする。
/// カレンダーの表示/非表示設定やカラー情報を提供する。
@MainActor
final class CalendarListService: ObservableObject {
    // MARK: - Published Properties

    /// カレンダーリスト
    @Published private(set) var calendars: [CalendarInfo] = []

    /// 同期中かどうか
    @Published private(set) var isSyncing: Bool = false

    /// 最終同期エラー
    @Published private(set) var lastError: Error?

    // MARK: - Dependencies

    private let apiClient: GoogleCalendarClient
    private let settings: CalendarSettings
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "CalendarListService")

    // MARK: - Initialization

    init(
        apiClient: GoogleCalendarClient,
        modelContext: ModelContext,
        settings: CalendarSettings = .shared
    ) {
        self.apiClient = apiClient
        self.modelContext = modelContext
        self.settings = settings
    }

    // MARK: - Public Methods

    /// ローカルのカレンダーリストを読み込む
    func loadLocalCalendars() async {
        do {
            let descriptor = FetchDescriptor<CalendarInfo>()
            var fetchedCalendars = try modelContext.fetch(descriptor)
            // プライマリカレンダーを先頭に、その後名前順でソート
            fetchedCalendars.sort { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary {
                    return lhs.isPrimary
                }
                return lhs.summary < rhs.summary
            }
            calendars = fetchedCalendars
            logger.info("Loaded \(self.calendars.count) calendars from local storage")
        } catch {
            logger.error("Failed to load local calendars: \(error.localizedDescription)")
            calendars = []
        }
    }

    /// カレンダーリストをGoogle Calendar APIから同期
    func syncCalendarList() async {
        guard !isSyncing else {
            logger.info("Calendar list sync already in progress")
            return
        }

        isSyncing = true
        lastError = nil

        do {
            try await performSync()
            settings.lastCalendarListSyncAt = Date()
            logger.info("Calendar list sync completed successfully")
        } catch CaleNoteError.apiError(.tokenExpired) {
            // syncTokenが失効した場合はフルリフレッシュ
            logger.warning("Calendar list syncToken expired, performing full refresh")
            settings.clearCalendarListSyncToken()
            do {
                try await performSync()
                settings.lastCalendarListSyncAt = Date()
            } catch {
                lastError = error
                logger.error("Full refresh failed: \(error.localizedDescription)")
            }
        } catch {
            lastError = error
            logger.error("Calendar list sync failed: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    /// カレンダーの表示/非表示を切り替え
    /// - Parameter calendarId: カレンダーID
    func toggleCalendarVisibility(_ calendarId: String) {
        guard let calendar = calendars.first(where: { $0.calendarId == calendarId }) else {
            return
        }
        calendar.toggleVisibility()
        do {
            try modelContext.save()
            logger.info("Toggled visibility for calendar: \(calendarId) to \(calendar.isVisible)")
        } catch {
            logger.error("Failed to save visibility change: \(error.localizedDescription)")
        }
    }

    /// カレンダーの同期設定を切り替え
    /// - Parameter calendarId: カレンダーID
    func toggleCalendarSync(_ calendarId: String) {
        guard let calendar = calendars.first(where: { $0.calendarId == calendarId }) else {
            return
        }
        calendar.toggleSync()
        do {
            try modelContext.save()
            logger.info("Toggled sync for calendar: \(calendarId) to \(calendar.isSyncEnabled)")
        } catch {
            logger.error("Failed to save sync change: \(error.localizedDescription)")
        }
    }

    /// 表示中のカレンダーIDリストを取得
    var visibleCalendarIds: Set<String> {
        Set(calendars.filter { $0.isVisible }.map { $0.calendarId })
    }

    /// 同期対象のカレンダーIDリストを取得
    var syncEnabledCalendarIds: Set<String> {
        Set(calendars.filter { $0.isSyncEnabled }.map { $0.calendarId })
    }

    /// カレンダーIDから背景色を取得
    /// - Parameter calendarId: カレンダーID
    /// - Returns: 背景色（16進数文字列）、見つからない場合はnil
    func backgroundColor(for calendarId: String?) -> String? {
        guard let calendarId = calendarId else { return nil }
        return calendars.first { $0.calendarId == calendarId }?.backgroundColor
    }

    /// カレンダーIDからカレンダー情報を取得
    /// - Parameter calendarId: カレンダーID
    /// - Returns: カレンダー情報、見つからない場合はnil
    func calendarInfo(for calendarId: String?) -> CalendarInfo? {
        guard let calendarId = calendarId else { return nil }
        return calendars.first { $0.calendarId == calendarId }
    }

    /// プライマリカレンダーを取得
    var primaryCalendar: CalendarInfo? {
        calendars.first { $0.isPrimary }
    }

    // MARK: - Private Methods

    /// 同期処理を実行
    private func performSync() async throws {
        var allCalendars: [CalendarListEntry] = []
        var pageToken: String? = nil
        let syncToken = settings.calendarListSyncToken

        // ページネーションでカレンダーリストを取得
        repeat {
            let response = try await apiClient.getCalendarList(
                pageToken: pageToken,
                syncToken: pageToken == nil ? syncToken : nil
            )

            if let items = response.items {
                allCalendars.append(contentsOf: items)
            }

            pageToken = response.nextPageToken

            // 新しいsyncTokenを保存
            if let newSyncToken = response.nextSyncToken {
                settings.calendarListSyncToken = newSyncToken
            }
        } while pageToken != nil

        // ローカルデータを更新
        try await updateLocalCalendars(from: allCalendars)

        // 更新後のリストを再読み込み
        await loadLocalCalendars()
    }

    /// ローカルカレンダーデータを更新
    private func updateLocalCalendars(from entries: [CalendarListEntry]) async throws {
        // 既存のカレンダーを取得
        let descriptor = FetchDescriptor<CalendarInfo>()
        let existingCalendars = try modelContext.fetch(descriptor)
        let existingMap = Dictionary(uniqueKeysWithValues: existingCalendars.map { ($0.calendarId, $0) })

        // 受信したカレンダーIDセット
        let receivedIds = Set(entries.map { $0.id })

        // 新規または更新
        for entry in entries {
            if let existing = existingMap[entry.id] {
                // 既存のカレンダーを更新
                existing.update(from: entry)
            } else {
                // 新規カレンダーを作成
                let newCalendar = CalendarInfo.from(entry)
                modelContext.insert(newCalendar)
                logger.info("Added new calendar: \(entry.id)")
            }
        }

        // 削除されたカレンダーを処理（同期トークンを使用した場合はスキップ）
        if settings.calendarListSyncToken == nil {
            for existing in existingCalendars {
                if !receivedIds.contains(existing.calendarId) {
                    modelContext.delete(existing)
                    logger.info("Deleted calendar: \(existing.calendarId)")
                }
            }
        }

        try modelContext.save()
    }
}
