//
//  DataRecoveryService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//
import Foundation
import SwiftData

/// データ復旧サービス
/// ローカルデータ破損時にGoogle Calendarから完全再構築を行う
@MainActor
final class DataRecoveryService {

    // MARK: - Progress Tracking

    struct RecoveryProgress {
        var phase: RecoveryPhase = .idle
        var currentCalendarId: String = ""
        var fetchedRanges: Int = 0
        var totalRanges: Int = 0
        var totalUpserted: Int = 0
        var totalDeleted: Int = 0
        var errorMessage: String?
    }

    enum RecoveryPhase: String {
        case idle = "待機中"
        case deletingLocalData = "ローカルデータを削除中"
        case syncingCalendarList = "カレンダー一覧を同期中"
        case fetchingEvents = "イベントを取得中"
        case rebuildingIndexes = "インデックスを再構築中"
        case completed = "完了"
        case failed = "失敗"
    }

    // MARK: - Integrity Check

    struct IntegrityCheckResult {
        var isHealthy: Bool
        var journalCount: Int
        var cachedEventCount: Int
        var archivedEventCount: Int
        var calendarCount: Int
        var orphanedJournalCount: Int  // linkedEventIdがあるがイベントが存在しないジャーナル
        var issues: [String]
    }

    /// データベースの整合性をチェック
    func checkIntegrity(modelContext: ModelContext) -> IntegrityCheckResult {
        var issues: [String] = []

        // 各モデルのカウント取得
        let journalCount = (try? modelContext.fetchCount(FetchDescriptor<JournalEntry>())) ?? 0
        let cachedEventCount = (try? modelContext.fetchCount(FetchDescriptor<CachedCalendarEvent>())) ?? 0
        let archivedEventCount = (try? modelContext.fetchCount(FetchDescriptor<ArchivedCalendarEvent>())) ?? 0
        let calendarCount = (try? modelContext.fetchCount(FetchDescriptor<CachedCalendar>())) ?? 0

        // リンク済みジャーナルの孤立チェック
        let linkedJournalPredicate = #Predicate<JournalEntry> { $0.linkedEventId != nil }
        let linkedJournals = (try? modelContext.fetch(FetchDescriptor(predicate: linkedJournalPredicate))) ?? []

        var orphanedCount = 0
        for journal in linkedJournals {
            guard let calendarId = journal.linkedCalendarId,
                  let eventId = journal.linkedEventId else { continue }

            let uid = "\(calendarId):\(eventId)"

            // 短期キャッシュか長期キャッシュに存在するかチェック
            let cachedPredicate = #Predicate<CachedCalendarEvent> { $0.uid == uid }
            let cachedExists = (try? modelContext.fetchCount(FetchDescriptor(predicate: cachedPredicate))) ?? 0 > 0

            let archivedPredicate = #Predicate<ArchivedCalendarEvent> { $0.uid == uid }
            let archivedExists = (try? modelContext.fetchCount(FetchDescriptor(predicate: archivedPredicate))) ?? 0 > 0

            if !cachedExists && !archivedExists {
                orphanedCount += 1
            }
        }

        if orphanedCount > 0 {
            issues.append("\(orphanedCount)件のジャーナルがリンク先イベントを失っています")
        }

        // カレンダーが0件の場合は警告
        if calendarCount == 0 {
            issues.append("カレンダー情報がありません")
        }

        // 重大な問題: 全データが0件（初回起動を除く）
        let hasAnyData = journalCount > 0 || cachedEventCount > 0 || archivedEventCount > 0
        if !hasAnyData && calendarCount > 0 {
            issues.append("カレンダーはあるがイベントデータがありません")
        }

        return IntegrityCheckResult(
            isHealthy: issues.isEmpty,
            journalCount: journalCount,
            cachedEventCount: cachedEventCount,
            archivedEventCount: archivedEventCount,
            calendarCount: calendarCount,
            orphanedJournalCount: orphanedCount,
            issues: issues
        )
    }

    // MARK: - Full Recovery

    /// Google Calendarからの完全再構築
    /// - Parameters:
    ///   - auth: 認証サービス
    ///   - modelContext: SwiftData コンテキスト
    ///   - preserveJournals: ジャーナルを保持するか（trueの場合、ジャーナルは削除せずリンクのみリセット）
    ///   - onProgress: 進捗コールバック
    func performFullRecovery(
        auth: GoogleAuthService,
        modelContext: ModelContext,
        preserveJournals: Bool = true,
        onProgress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws {

        var progress = RecoveryProgress()

        // ログ記録開始
        let syncLog = SyncLog(
            syncType: "recovery",
            calendarIdHash: nil
        )
        modelContext.insert(syncLog)

        do {
            // Phase 1: ローカルデータの削除
            progress.phase = .deletingLocalData
            onProgress(progress)

            try await deleteLocalData(
                modelContext: modelContext,
                preserveJournals: preserveJournals
            )
            try modelContext.save()

            // Phase 2: カレンダー一覧の同期
            progress.phase = .syncingCalendarList
            onProgress(progress)

            let calendarListSync = CalendarListSyncService()
            try await calendarListSync.syncCalendarList(
                auth: auth,
                modelContext: modelContext
            )
            try modelContext.save()

            // Phase 3: イベントの取得
            progress.phase = .fetchingEvents
            onProgress(progress)

            // 有効なカレンダーを取得
            let calendars = try modelContext.fetch(FetchDescriptor<CachedCalendar>())
            let enabledCalendars = calendars.filter { $0.isEnabled }

            if !enabledCalendars.isEmpty {
                let archiveSync = ArchiveSyncService()

                try await archiveSync.importAllEventsToArchive(
                    auth: auth,
                    modelContext: modelContext,
                    calendars: enabledCalendars
                ) { archiveProgress in
                    Task { @MainActor in
                        progress.currentCalendarId = archiveProgress.calendarId
                        progress.fetchedRanges = archiveProgress.fetchedRanges
                        progress.totalRanges = archiveProgress.totalRanges
                        progress.totalUpserted += archiveProgress.upserted
                        progress.totalDeleted += archiveProgress.deleted
                        onProgress(progress)
                    }
                }
            }

            // Phase 4: インデックスの再構築（短期キャッシュの同期）
            progress.phase = .rebuildingIndexes
            onProgress(progress)

            // syncTokenをクリアしてフル同期
            clearAllSyncTokens(calendars: enabledCalendars)

            let calendarSync = CalendarSyncService()
            let syncSettings = SyncSettings.self
            let now = Date()
            let timeMin = Calendar.current.date(byAdding: .day, value: -syncSettings.pastDays(), to: now) ?? now
            let timeMax = Calendar.current.date(byAdding: .day, value: syncSettings.futureDays(), to: now) ?? now

            try await calendarSync.syncEnabledCalendars(
                auth: auth,
                modelContext: modelContext,
                calendars: enabledCalendars,
                initialTimeMin: timeMin,
                initialTimeMax: timeMax
            )

            // ジャーナルのリンク再構築
            if preserveJournals {
                try await relinkJournals(
                    modelContext: modelContext
                )
            }

            try modelContext.save()

            // Phase 5: 完了
            progress.phase = .completed
            onProgress(progress)

            // ログ記録（成功）
            syncLog.endTimestamp = Date()
            syncLog.updatedCount = progress.totalUpserted
            syncLog.deletedCount = progress.totalDeleted
            syncLog.httpStatusCode = 200
            try modelContext.save()

        } catch is CancellationError {
            progress.phase = .failed
            progress.errorMessage = "復旧がキャンセルされました"
            onProgress(progress)

            syncLog.endTimestamp = Date()
            syncLog.errorType = "CancellationError"
            syncLog.errorMessage = "復旧がキャンセルされました"
            try? modelContext.save()

            throw CancellationError()
        } catch {
            progress.phase = .failed
            progress.errorMessage = error.localizedDescription
            onProgress(progress)

            syncLog.endTimestamp = Date()
            syncLog.errorType = String(describing: type(of: error))
            syncLog.errorMessage = error.localizedDescription
            syncLog.httpStatusCode = SyncErrorReporter.extractHttpStatusCode(from: error)
            try? modelContext.save()

            SyncErrorReporter.reportSyncFailure(
                error: error,
                syncType: "recovery",
                calendarId: "all",
                phase: "full_recovery",
                had410Fallback: false,
                httpStatusCode: syncLog.httpStatusCode
            )

            throw error
        }
    }

    // MARK: - Private Methods

    /// ローカルデータを削除
    private func deleteLocalData(
        modelContext: ModelContext,
        preserveJournals: Bool
    ) async throws {

        // CachedCalendarEvent を全削除
        let cachedEvents = try modelContext.fetch(FetchDescriptor<CachedCalendarEvent>())
        for event in cachedEvents {
            modelContext.delete(event)
        }

        // ArchivedCalendarEvent を全削除
        let archivedEvents = try modelContext.fetch(FetchDescriptor<ArchivedCalendarEvent>())
        for event in archivedEvents {
            modelContext.delete(event)
        }

        // CachedCalendar を全削除
        let calendars = try modelContext.fetch(FetchDescriptor<CachedCalendar>())
        for calendar in calendars {
            modelContext.delete(calendar)
        }

        // SyncLog を全削除（復旧後にクリーンな状態にする）
        let syncLogs = try modelContext.fetch(FetchDescriptor<SyncLog>())
        for log in syncLogs {
            modelContext.delete(log)
        }

        if preserveJournals {
            // ジャーナルは保持するが、リンク情報をリセット
            let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
            for journal in journals {
                journal.linkedCalendarId = nil
                journal.linkedEventId = nil
                journal.linkedEventUpdatedAt = nil
                journal.needsCalendarSync = true  // 再同期が必要
                journal.hasConflict = false
                journal.conflictDetectedAt = nil
                journal.conflictRemoteTitle = nil
                journal.conflictRemoteBody = nil
                journal.conflictRemoteUpdatedAt = nil
                journal.conflictRemoteEventDate = nil
            }
        } else {
            // ジャーナルも削除
            let journals = try modelContext.fetch(FetchDescriptor<JournalEntry>())
            for journal in journals {
                modelContext.delete(journal)
            }
        }

        // ArchiveSyncServiceの進捗もクリア
        UserDefaults.standard.removeObject(forKey: "ArchiveSyncService.SavedProgress")
    }

    /// 全カレンダーのsyncTokenをクリア
    private func clearAllSyncTokens(calendars: [CachedCalendar]) {
        for calendar in calendars {
            CalendarSyncState.saveSyncToken(nil, calendarId: calendar.calendarId)
        }
    }

    /// ジャーナルとカレンダーイベントの再リンク
    /// Google Calendar側のextendedProperties.privateにあるjournalIdを使って再リンク
    private func relinkJournals(modelContext: ModelContext) async throws {
        // journalIdを持つキャッシュイベントを取得
        let cachedEvents = try modelContext.fetch(FetchDescriptor<CachedCalendarEvent>())

        for event in cachedEvents {
            guard let journalIdString = event.linkedJournalId,
                  let journalId = UUID(uuidString: journalIdString) else { continue }

            // 対応するジャーナルを検索
            let predicate = #Predicate<JournalEntry> { $0.id == journalId }
            let journals = try modelContext.fetch(FetchDescriptor(predicate: predicate))

            if let journal = journals.first {
                // リンクを再構築
                journal.linkedCalendarId = event.calendarId
                journal.linkedEventId = event.eventId
                journal.linkedEventUpdatedAt = event.updatedAt
                journal.needsCalendarSync = false
            }
        }
    }
}
