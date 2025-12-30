//
//  CalendarSyncService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Foundation
import SwiftData
import OSLog
import Combine

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

    private let apiClient: GoogleCalendarClient
    private let authService: GoogleAuthService
    private let searchIndexService: SearchIndexService
    private let errorHandler: ErrorHandler
    private let modelContext: ModelContext
    private let calendarSettings: CalendarSettings
    private let rateLimiter: SyncRateLimiter

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "CalendarSync")

    // MARK: - Sync State

    /// カレンダーごとの syncToken を保存
    private var syncTokens: [String: String] = [:]

    /// 同期設定
    private let syncConfig = SyncConfiguration()

    // MARK: - Background Task

    private var syncTimer: Timer?

    // MARK: - Initialization

    init(
        apiClient: GoogleCalendarClient,
        authService: GoogleAuthService,
        searchIndexService: SearchIndexService,
        errorHandler: ErrorHandler,
        modelContext: ModelContext,
        calendarSettings: CalendarSettings,
        rateLimiter: SyncRateLimiter
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.searchIndexService = searchIndexService
        self.errorHandler = errorHandler
        self.modelContext = modelContext
        self.calendarSettings = calendarSettings
        self.rateLimiter = rateLimiter

        // syncToken を復元
        loadSyncTokens()
    }

    // MARK: - Full Sync

    /// 完全同期を実行
    /// - Throws: 同期エラー
    func performFullSync() async throws {
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
        logger.info("Syncing Google changes to local (past: \(pastDays)d, future: \(futureDays)d)")

        // TODO: Issue #18 - 現在は全カレンダーを同期しているが、
        // 設定で指定されたカレンダーのみを同期するように変更する必要がある
        // 暫定的には全カレンダーを同期する実装とする

        // カレンダーリストを取得
        let calendarList = try await apiClient.getCalendarList()

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
                    pageToken: nextPageToken
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
            updateEntryFromEvent(existingEntry, event: event)
            searchIndexService.updateEntry(existingEntry)
            logger.info("Updated local entry from Google event: \(eventId)")
        } else {
            // 新規エントリーを作成（CaleNote 管理対象外のイベント）
            let newEntry = createEntryFromEvent(event, calendarId: calendarId)
            modelContext.insert(newEntry)
            searchIndexService.indexEntry(newEntry)
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
                entry.syncStatus == "pending"
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
            modelContext.delete(entry)
            searchIndexService.removeEntry(entry)
            try modelContext.save()
            logger.info("Deleted local entry: \(googleEventId)")
        }
    }

    // MARK: - Conversion

    /// ScheduleEntry を CalendarEvent に変換
    /// - Parameter entry: ScheduleEntry
    /// - Returns: CalendarEvent
    private func convertToCalendarEvent(_ entry: ScheduleEntry) -> CalendarEvent {
        // CaleNote 管理フラグを extendedProperties に保存
        let privateProperties = entry.managedByCaleNote ? ["managedByCaleNote": "true"] : nil
        let extendedProperties = privateProperties != nil
            ? CalendarEvent.ExtendedProperties(private: privateProperties, shared: nil)
            : nil

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
            startAt: startAt,
            endAt: endAt,
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
    private func updateEntryFromEvent(_ entry: ScheduleEntry, event: CalendarEvent) {
        entry.title = event.summary ?? "(タイトルなし)"
        entry.body = event.description
        entry.tags = TagParser.extract(from: [entry.title, entry.body])
        entry.startAt = parseEventDateTime(event.start)
        entry.endAt = parseEventDateTime(event.end)
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
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return Date()
    }

    // MARK: - Sync Token Persistence

    /// syncToken を UserDefaults から読み込み
    private func loadSyncTokens() {
        if let data = UserDefaults.standard.data(forKey: "CalendarSyncTokens"),
           let tokens = try? JSONDecoder().decode([String: String].self, from: data) {
            syncTokens = tokens
            logger.info("Loaded \(tokens.count) sync tokens")
        }
    }

    /// syncToken を UserDefaults に保存
    private func saveSyncTokens() {
        if let data = try? JSONEncoder().encode(self.syncTokens) {
            UserDefaults.standard.set(data, forKey: "CalendarSyncTokens")
            logger.info("Saved \(self.syncTokens.count) sync tokens")
        }
    }

    // MARK: - Recovery Helpers

    /// 同期トークンをリセット（完全同期用）
    func resetSyncTokens() {
        syncTokens.removeAll()
        saveSyncTokens()
        logger.info("Reset sync tokens")
    }

    // MARK: - Background Sync

    /// バックグラウンド同期を開始
    func startBackgroundSync() {
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
                entry.syncStatus == "failed"
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
