//
//  CalendarSyncService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import Foundation
import OSLog
import SwiftData

/// Google Calendar との双方向同期サービス
@MainActor
final class CalendarSyncService: ObservableObject {
    // MARK: - Published Properties

    /// 同期中フラグ
    @Published private(set) var isSyncing = false

    /// 最終同期時刻
    @Published private(set) var lastSyncTime: Date?

    /// 同期エラー
    @Published private(set) var lastSyncError: Error?

    /// 同期待ちエントリー数
    @Published private(set) var pendingSyncCount = 0

    // MARK: - Dependencies

    private let apiClient: GoogleCalendarClientProtocol
    private let authService: GoogleAuthService
    private let searchIndexService: SearchIndexService
    private let relatedIndexService: RelatedEntriesIndexService
    private let errorHandler: ErrorHandler
    private let modelContext: ModelContext
    private let calendarSettings: CalendarSettings
    private let rateLimiter: SyncRateLimiter
    private let trashSettings: TrashSettings

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "CalendarSync")

    // MARK: - Sync State

    /// カレンダーごとの syncToken を保存
    private var syncTokens: [String: String] = [:]
    private let syncTokenStore = SyncTokenStore()

    /// 同期設定
    private let syncConfig = SyncConfiguration()

    private var isSyncDisabled: Bool {
        AppEnvironment.shouldSkipSync
    }

    // MARK: - Background Task

    private var syncTimer: Timer?

    // MARK: - Initialization

    init(
        apiClient: GoogleCalendarClientProtocol,
        authService: GoogleAuthService,
        searchIndexService: SearchIndexService,
        relatedIndexService: RelatedEntriesIndexService,
        errorHandler: ErrorHandler,
        modelContext: ModelContext,
        calendarSettings: CalendarSettings,
        rateLimiter: SyncRateLimiter
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.searchIndexService = searchIndexService
        self.relatedIndexService = relatedIndexService
        self.errorHandler = errorHandler
        self.modelContext = modelContext
        self.calendarSettings = calendarSettings
        self.rateLimiter = rateLimiter
        self.trashSettings = .shared

        // syncToken を復元
        loadSyncTokens()
    }

    // MARK: - Full Sync

    /// 完全同期を実行
    /// - Throws: 同期エラー
    func performFullSync() async throws {
        if isSyncDisabled {
            lastSyncTime = Date()
            lastSyncError = nil
            return
        }

        logger.info("Starting full sync")
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            // 1. ローカル変更を Google に同期
            try await syncLocalChangesToGoogle()

            // 2. Google から変更を取得してローカルに反映
            try await syncGoogleChangesToLocal()

            lastSyncTime = Date()
            logger.info("Full sync completed successfully")
        } catch {
            lastSyncError = error
            logger.error("Full sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Local to Google Sync

    /// ローカル変更を Google Calendar に同期
    /// - Throws: 同期エラー
    func syncLocalChangesToGoogle() async throws {
        if isSyncDisabled {
            pendingSyncCount = 0
            return
        }

        logger.info("Syncing local changes to Google")

        // 同期待ちエントリーを取得
        let pendingEntries = try fetchPendingEntries()
        pendingSyncCount = pendingEntries.count

        logger.info("Found \(pendingEntries.count) pending entries")

        for entry in pendingEntries {
            do {
                try await syncEntryToGoogle(entry)
            } catch {
                // エラーが発生してもログを記録して次のエントリーへ進む
                logger.error("Failed to sync entry \(entry.googleEventId ?? entry.title): \(error.localizedDescription)")
                entry.syncStatus = ScheduleEntry.SyncStatus.failed.rawValue
                try modelContext.save()
            }
        }

        // カウント更新
        pendingSyncCount = try fetchPendingEntries().count
    }

    /// 単一エントリーを Google に同期
    /// - Parameter entry: 同期するエントリー
    /// - Throws: API エラー
    private func syncEntryToGoogle(_ entry: ScheduleEntry) async throws {
        logger.info("Syncing entry to Google: \(entry.googleEventId ?? entry.title)")

        // Google Calendar イベントに変換
        let calendarEvent = convertToCalendarEvent(entry)

        // 設定からカレンダーIDを取得
        let calendarId = calendarSettings.targetCalendarId

        if let googleEventId = entry.googleEventId {
            // 既存イベントを更新
            let updatedEvent = try await apiClient.updateEvent(
                calendarId: calendarId,
                eventId: googleEventId,
                event: calendarEvent
            )

            // 更新されたイベント情報で同期
            entry.googleEventId = updatedEvent.id
            entry.syncStatus = ScheduleEntry.SyncStatus.synced.rawValue
            entry.lastSyncedAt = Date()
        } else {
            // 新規イベントを作成
            let createdEvent = try await apiClient.createEvent(
                calendarId: calendarId,
                event: calendarEvent
            )

            // 作成されたイベント ID を保存
            entry.googleEventId = createdEvent.id
            entry.syncStatus = ScheduleEntry.SyncStatus.synced.rawValue
            entry.lastSyncedAt = Date()
        }

        try modelContext.save()
        logger.info("Successfully synced entry: \(entry.googleEventId ?? entry.title)")
    }

    // MARK: - Google to Local Sync

    /// Google Calendar の変更をローカルに同期
    /// - Throws: 同期エラー
    func syncGoogleChangesToLocal() async throws {
        if isSyncDisabled { return }

        try await syncGoogleChangesToLocal(
            pastDays: syncConfig.pastDays,
            futureDays: syncConfig.futureDays
        )
    }

    /// Google Calendar の変更をローカルに同期（同期範囲を指定）
    /// - Parameters:
    ///   - pastDays: 過去の同期範囲（日数）
    ///   - futureDays: 未来の同期範囲（日数）
    /// - Throws: 同期エラー
    func syncGoogleChangesToLocal(pastDays: Int, futureDays: Int) async throws {
        if isSyncDisabled { return }

        logger.info("Syncing Google changes to local (past: \(pastDays)d, future: \(futureDays)d)")

        // TODO: Issue #18 - 現在は全カレンダーを同期しているが、
        // 設定で指定されたカレンダーのみを同期するように変更する必要がある
        // 暫定的には全カレンダーを同期する実装とする

        // カレンダーリストを取得
        let calendarList = try await apiClient.getCalendarList(pageToken: nil, syncToken: nil)

        guard let calendars = calendarList.items else {
            logger.warning("No calendars found")
            return
        }

        // 各カレンダーのイベントを同期
        for calendar in calendars {
            do {
                try await syncCalendarEvents(
                    calendar.id,
                    pastDays: pastDays,
                    futureDays: futureDays
                )
            } catch CaleNoteError.apiError(.tokenExpired) {
                // syncToken が失効した場合はトークンをクリアして再試行
                logger.warning("SyncToken expired for calendar: \(calendar.id), performing full sync")
                syncTokens.removeValue(forKey: calendar.id)
                try await syncCalendarEvents(
                    calendar.id,
                    pastDays: pastDays,
                    futureDays: futureDays
                )
            } catch {
                logger.error("Failed to sync calendar \(calendar.id): \(error.localizedDescription)")
                // エラーが発生しても他のカレンダーの同期を続行
            }
        }

        // syncToken を保存
        saveSyncTokens()
    }

    /// 指定カレンダーのイベントを同期
    /// - Parameter calendarId: カレンダー ID
    /// - Throws: API エラー
    private func syncCalendarEvents(
        _ calendarId: String,
        pastDays: Int,
        futureDays: Int
    ) async throws {
        logger.info("Syncing events for calendar: \(calendarId)")

        let syncToken = syncTokens[calendarId]
        var nextPageToken: String?
        var allEvents: [CalendarEvent] = []

        // syncToken がある場合は差分同期、ない場合は完全同期
        if let syncToken = syncToken {
            // 差分同期
            do {
                try await rateLimiter.acquire()
                let response = try await apiClient.listEventsSince(
                    calendarId: calendarId,
                    syncToken: syncToken
                )
                allEvents = response.items ?? []

                // 新しい syncToken を保存
                if let newSyncToken = response.nextSyncToken {
                    syncTokens[calendarId] = newSyncToken
                }
            } catch CaleNoteError.apiError(.tokenExpired) {
                // syncToken が失効した場合は再スロー
                throw CaleNoteError.apiError(.tokenExpired)
            }
        } else {
            // 完全同期（時間範囲を指定）
            let now = Date()
            guard let pastDate = Calendar.current.date(
                byAdding: .day,
                value: -pastDays,
                to: now
            ),
            let futureDate = Calendar.current.date(
                byAdding: .day,
                value: futureDays,
                to: now
            ) else {
                logger.error("Failed to calculate sync date range")
                return
            }

            let timeMin = GoogleCalendarClient.iso8601String(from: pastDate)
            let timeMax = GoogleCalendarClient.iso8601String(from: futureDate)

            // ページネーション対応
            repeat {
                try await rateLimiter.acquire()
                let response = try await apiClient.listEvents(
                    calendarId: calendarId,
                    timeMin: timeMin,
                    timeMax: timeMax,
                    pageToken: nextPageToken,
                    syncToken: nil,
                    maxResults: 250
                )

                if let items = response.items {
                    allEvents.append(contentsOf: items)
                }

                nextPageToken = response.nextPageToken

                // syncToken を保存（最後のページで取得）
                if nextPageToken == nil, let syncToken = response.nextSyncToken {
                    syncTokens[calendarId] = syncToken
                }
            } while nextPageToken != nil
        }

        logger.info("Fetched \(allEvents.count) events from calendar: \(calendarId)")

        // イベントをローカルに反映
        for event in allEvents {
            try await applyEventToLocal(event, calendarId: calendarId)
        }
    }

    /// Google Calendar イベントをローカルに反映
    /// - Parameters:
    ///   - event: Google Calendar イベント
    ///   - calendarId: カレンダー ID
    /// - Throws: データベースエラー
    private func applyEventToLocal(_ event: CalendarEvent, calendarId: String) async throws {
        // イベントが削除されている場合
        if event.status == "cancelled" {
            if let eventId = event.id {
                try await deleteLocalEvent(googleEventId: eventId)
            }
            return
        }

        // 既存エントリーを検索
        if let eventId = event.id,
           let existingEntry = try fetchEntry(googleEventId: eventId) {
            // 既存エントリーを更新（Google を正とする）
            updateEntryFromEvent(existingEntry, event: event, calendarId: calendarId)
            searchIndexService.updateEntry(existingEntry)
            relatedIndexService.updateEntry(existingEntry)
            logger.info("Updated local entry from Google event: \(eventId)")
        } else {
            // 新規エントリーを作成（CaleNote 管理対象外のイベント）
            let newEntry = createEntryFromEvent(event, calendarId: calendarId)
            modelContext.insert(newEntry)
            searchIndexService.indexEntry(newEntry)
            relatedIndexService.indexEntry(newEntry)
            logger.info("Created new local entry from Google event: \(event.id ?? "unknown")")
        }

        try modelContext.save()
    }

    // MARK: - Entry Management

    /// 同期待ちエントリーを取得
    /// - Returns: 同期待ちエントリー配列
    /// - Throws: データベースエラー
    private func fetchPendingEntries() throws -> [ScheduleEntry] {
        let descriptor = FetchDescriptor<ScheduleEntry>(
            predicate: #Predicate { entry in
                entry.syncStatus == "pending" && entry.isDeleted == false
            }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Google Event ID でエントリーを取得
    /// - Parameter googleEventId: Google Event ID
    /// - Returns: エントリー（見つからない場合は nil）
    /// - Throws: データベースエラー
    private func fetchEntry(googleEventId: String) throws -> ScheduleEntry? {
        let descriptor = FetchDescriptor<ScheduleEntry>(
            predicate: #Predicate { entry in
                entry.googleEventId == googleEventId
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// ローカルイベントを削除
    /// - Parameter googleEventId: Google Event ID
    /// - Throws: データベースエラー
    private func deleteLocalEvent(googleEventId: String) async throws {
        if let entry = try fetchEntry(googleEventId: googleEventId) {
            if trashSettings.isEnabled {
                markEntryDeleted(entry)
                try modelContext.save()
                logger.info("Soft deleted local entry: \(googleEventId)")
            } else {
                modelContext.delete(entry)
                searchIndexService.removeEntry(entry)
                relatedIndexService.removeEntry(entry)
                try modelContext.save()
                logger.info("Deleted local entry: \(googleEventId)")
            }
        }
    }

    // MARK: - Delete

    /// エントリーを削除（Google とローカル）
    /// - Parameter entry: 削除対象エントリー
    func deleteEntry(_ entry: ScheduleEntry) async throws {
        logger.info("Deleting entry: \(entry.googleEventId ?? entry.title)")

        if let eventId = entry.googleEventId {
            let calendarId = calendarSettings.targetCalendarId
            try await apiClient.deleteEvent(calendarId: calendarId, eventId: eventId)
        }

        if trashSettings.isEnabled {
            markEntryDeleted(entry)
            try modelContext.save()
            logger.info("Moved entry to trash: \(entry.title)")
        } else {
            modelContext.delete(entry)
            searchIndexService.removeEntry(entry)
            relatedIndexService.removeEntry(entry)
            try modelContext.save()
            logger.info("Deleted entry locally: \(entry.googleEventId ?? entry.title)")
        }
    }

    /// ゴミ箱から復元（Google Calendar に再作成）
    /// - Parameter entry: 復元対象エントリー
    func restoreEntry(_ entry: ScheduleEntry) async throws {
        logger.info("Restoring entry: \(entry.title)")
        let calendarId = calendarSettings.targetCalendarId
        entry.googleEventId = nil
        let calendarEvent = convertToCalendarEvent(entry)

        let createdEvent = try await apiClient.createEvent(
            calendarId: calendarId,
            event: calendarEvent
        )

        entry.restoreFromTrash()
        entry.calendarId = calendarId
        entry.googleEventId = createdEvent.id
        entry.syncStatus = ScheduleEntry.SyncStatus.synced.rawValue
        entry.lastSyncedAt = Date()
        searchIndexService.indexEntry(entry)
        relatedIndexService.indexEntry(entry)
        try modelContext.save()
        logger.info("Restored entry with new event ID: \(createdEvent.id ?? "unknown")")
    }

    /// ローカルから完全削除
    func purgeEntry(_ entry: ScheduleEntry) throws {
        logger.info("Purging entry: \(entry.title)")
        modelContext.delete(entry)
        searchIndexService.removeEntry(entry)
        relatedIndexService.removeEntry(entry)
        try modelContext.save()
    }

    /// ゴミ箱を空にする
    func purgeAllTrashEntries() throws {
        let descriptor = FetchDescriptor<ScheduleEntry>(
            predicate: #Predicate { entry in
                entry.isDeleted == true
            }
        )
        let entries = try modelContext.fetch(descriptor)
        for entry in entries {
            modelContext.delete(entry)
            searchIndexService.removeEntry(entry)
            relatedIndexService.removeEntry(entry)
        }
        if !entries.isEmpty {
            try modelContext.save()
        }
        logger.info("Purged trash entries: \(entries.count)")
    }

    /// 期限切れゴミ箱の自動削除
    func cleanupExpiredTrashEntries() throws {
        guard trashSettings.isEnabled, trashSettings.autoPurgeEnabled else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -trashSettings.retentionDays, to: Date()) else {
            return
        }

        let descriptor = FetchDescriptor<ScheduleEntry>(
            predicate: #Predicate { entry in
                entry.isDeleted == true && entry.deletedAt != nil && entry.deletedAt! <= cutoff
            }
        )

        let expired = try modelContext.fetch(descriptor)
        for entry in expired {
            modelContext.delete(entry)
            searchIndexService.removeEntry(entry)
            relatedIndexService.removeEntry(entry)
        }
        if !expired.isEmpty {
            try modelContext.save()
        }
        logger.info("Cleaned up expired trash entries: \(expired.count)")
    }

    // MARK: - Conversion

    /// 論理削除処理（インデックスから除外）
    /// - Parameters:
    ///   - entry: 対象エントリー
    ///   - deletedAt: 削除日時
    private func markEntryDeleted(_ entry: ScheduleEntry, deletedAt: Date = Date()) {
        entry.markDeleted(at: deletedAt)
        entry.googleEventId = nil
        entry.syncStatus = ScheduleEntry.SyncStatus.synced.rawValue
        entry.lastSyncedAt = Date()
        searchIndexService.removeEntry(entry)
        relatedIndexService.removeEntry(entry)
    }

    /// ScheduleEntry を CalendarEvent に変換
    /// - Parameter entry: ScheduleEntry
    /// - Returns: CalendarEvent
    private func convertToCalendarEvent(_ entry: ScheduleEntry) -> CalendarEvent {
        // CaleNote 管理フラグを extendedProperties に保存
        let privateProperties = entry.managedByCaleNote ? ["managedByCaleNote": "true"] : nil
        let extendedProperties = privateProperties != nil
            ? CalendarEvent.ExtendedProperties(private: privateProperties, shared: nil)
            : nil

        if entry.isAllDay {
            let (startDate, endDate) = allDayDateRange(for: entry)
            return CalendarEvent(
                id: entry.googleEventId,
                status: nil,
                summary: entry.title,
                description: entry.body,
                start: CalendarEvent.EventDateTime(
                    date: startDate,
                    dateTime: nil,
                    timeZone: nil
                ),
                end: CalendarEvent.EventDateTime(
                    date: endDate,
                    dateTime: nil,
                    timeZone: nil
                ),
                created: nil,
                updated: nil,
                etag: nil,
                extendedProperties: extendedProperties,
                recurrence: nil,
                recurringEventId: nil,
                originalStartTime: nil
            )
        }

        return CalendarEvent(
            id: entry.googleEventId,
            status: nil,
            summary: entry.title,
            description: entry.body,
            start: CalendarEvent.EventDateTime(
                date: nil,
                dateTime: GoogleCalendarClient.iso8601String(from: entry.startAt),
                timeZone: TimeZone.current.identifier
            ),
            end: CalendarEvent.EventDateTime(
                date: nil,
                dateTime: GoogleCalendarClient.iso8601String(from: entry.endAt),
                timeZone: TimeZone.current.identifier
            ),
            created: nil,
            updated: nil,
            etag: nil,
            extendedProperties: extendedProperties,
            recurrence: nil,
            recurringEventId: nil,
            originalStartTime: nil
        )
    }

    /// CalendarEvent から新規 ScheduleEntry を作成
    /// - Parameters:
    ///   - event: CalendarEvent
    ///   - calendarId: カレンダー ID
    /// - Returns: ScheduleEntry
    private func createEntryFromEvent(_ event: CalendarEvent, calendarId: String) -> ScheduleEntry {
        let isManagedByCaleNote = event.extendedProperties?.private?["managedByCaleNote"] == "true"

        // 全日イベントかどうかを判定
        let isAllDay = event.start?.date != nil

        // startAt と endAt を取得
        let startAt = parseEventDateTime(event.start)
        let endAt = parseEventDateTime(event.end)
        let title = event.summary ?? "(タイトルなし)"
        let body = event.description
        let tags = TagParser.extract(from: [title, body])

        return ScheduleEntry(
            source: ScheduleEntry.Source.google.rawValue,
            managedByCaleNote: isManagedByCaleNote,
            googleEventId: event.id,
            calendarId: calendarId,
            startAt: startAt,
            endAt: endAt,
            isAllDay: isAllDay,
            title: title,
            body: body,
            tags: tags,
            syncStatus: ScheduleEntry.SyncStatus.synced.rawValue,
            lastSyncedAt: Date()
        )
    }

    /// 既存 ScheduleEntry を CalendarEvent で更新（Google を正とする）
    /// - Parameters:
    ///   - entry: ScheduleEntry
    ///   - event: CalendarEvent
    ///   - calendarId: カレンダー ID
    private func updateEntryFromEvent(_ entry: ScheduleEntry, event: CalendarEvent, calendarId: String) {
        entry.title = event.summary ?? "(タイトルなし)"
        entry.body = event.description
        entry.tags = TagParser.extract(from: [entry.title, entry.body])
        entry.startAt = parseEventDateTime(event.start)
        entry.endAt = parseEventDateTime(event.end)
        entry.isAllDay = event.start?.date != nil
        entry.calendarId = calendarId
        if entry.isDeleted {
            entry.restoreFromTrash()
        }
        entry.syncStatus = ScheduleEntry.SyncStatus.synced.rawValue
        entry.lastSyncedAt = Date()
        entry.updatedAt = Date()
    }

    /// EventDateTime を Date に変換
    /// - Parameter eventDateTime: EventDateTime
    /// - Returns: Date
    private func parseEventDateTime(_ eventDateTime: CalendarEvent.EventDateTime?) -> Date {
        guard let eventDateTime = eventDateTime else {
            return Date()
        }

        // dateTime がある場合は ISO 8601 でパース
        if let dateTimeString = eventDateTime.dateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTimeString) {
                return date
            }
            // フラクショナル秒なしでも試す
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateTimeString) {
                return date
            }
        }

        // date がある場合は日付のみ
        if let dateString = eventDateTime.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return Date()
    }

    /// 全日イベント用の日付レンジ（Google Calendar は end が排他的）
    private func allDayDateRange(for entry: ScheduleEntry) -> (startDate: String, endDate: String) {
        let calendar = Calendar.current
        let span = entry.allDaySpan(using: calendar)
        let startDate = allDayDateString(from: span.startDay, calendar: calendar)
        let endDate = allDayDateString(from: span.endDayExclusive, calendar: calendar)
        return (startDate, endDate)
    }

    private func allDayDateString(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Sync Token Persistence

    /// syncToken を UserDefaults から読み込み
    private func loadSyncTokens() {
        let tokens = syncTokenStore.load()
        syncTokens = tokens
        if !tokens.isEmpty {
            logger.info("Loaded \(tokens.count) sync tokens")
        }
    }

    /// syncToken を UserDefaults に保存
    private func saveSyncTokens() {
        syncTokenStore.save(syncTokens)
        logger.info("Saved \(self.syncTokens.count) sync tokens")
    }

    // MARK: - Recovery Helpers

    /// 同期トークンをリセット（完全同期用）
    func resetSyncTokens() {
        syncTokens.removeAll()
        syncTokenStore.clear()
        logger.info("Reset sync tokens")
    }

    // MARK: - Background Sync

    /// フォアグラウンド復帰時の即時同期
    func performForegroundSync() async {
        if isSyncDisabled { return }

        guard !isSyncing else { return }
        do {
            try await performFullSync()
        } catch {
            logger.error("Foreground sync failed: \(error.localizedDescription)")
        }
    }

    /// バックグラウンド同期を開始
    func startBackgroundSync() {
        if isSyncDisabled { return }

        logger.info("Starting background sync with interval: \(self.syncConfig.syncInterval)s")

        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(
            withTimeInterval: self.syncConfig.syncInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                do {
                    try await self.performFullSync()
                } catch {
                    self.logger.error("Background sync failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// バックグラウンド同期を停止
    func stopBackgroundSync() {
        logger.info("Stopping background sync")
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Retry Failed Syncs

    /// 失敗した同期を再試行
    /// - Throws: 同期エラー
    func retryFailedSyncs() async throws {
        if isSyncDisabled { return }

        logger.info("Retrying failed syncs")

        // 失敗したエントリーを pending に戻す
        let failedEntries = try fetchFailedEntries()
        for entry in failedEntries {
            entry.syncStatus = ScheduleEntry.SyncStatus.pending.rawValue
        }
        try modelContext.save()

        // 同期実行
        try await syncLocalChangesToGoogle()
    }

    /// 失敗したエントリーを取得
    /// - Returns: 失敗したエントリー配列
    /// - Throws: データベースエラー
    private func fetchFailedEntries() throws -> [ScheduleEntry] {
        let descriptor = FetchDescriptor<ScheduleEntry>(
            predicate: #Predicate { entry in
                entry.syncStatus == "failed" && entry.isDeleted == false
            }
        )
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Sync Configuration

/// 同期設定
struct SyncConfiguration {
    /// 同期間隔（秒）
    let syncInterval: TimeInterval = 300 // 5分

    /// 過去の同期範囲（日数）
    let pastDays: Int = 90 // 3ヶ月

    /// 未来の同期範囲（日数）
    let futureDays: Int = 365 // 1年
}
