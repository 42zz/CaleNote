import Foundation
import SwiftData

@MainActor
final class ArchiveSyncService {

    struct Progress {
        var calendarId: String = ""
        var fetchedRanges: Int = 0
        var totalRanges: Int = 0
        var upserted: Int = 0
        var deleted: Int = 0
    }

    // 進捗状態の保存・復元
    private struct SavedProgress: Codable {
        var calendarId: String
        var completedRangeIndex: Int  // 最後に完了したレンジのインデックス
    }

    private let progressKey = "ArchiveSyncService.SavedProgress"

    private func loadProgress(for calendarId: String) -> Int? {
        guard let data = UserDefaults.standard.data(forKey: progressKey),
              let saved = try? JSONDecoder().decode([SavedProgress].self, from: data) else {
            return nil
        }
        return saved.first { $0.calendarId == calendarId }?.completedRangeIndex
    }

    private func saveProgress(calendarId: String, completedRangeIndex: Int) {
        var saved: [SavedProgress] = []
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let existing = try? JSONDecoder().decode([SavedProgress].self, from: data) {
            saved = existing.filter { $0.calendarId != calendarId }
        }
        saved.append(SavedProgress(calendarId: calendarId, completedRangeIndex: completedRangeIndex))
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: progressKey)
        }
    }

    private func clearProgress(for calendarId: String) {
        guard let data = UserDefaults.standard.data(forKey: progressKey),
              var saved = try? JSONDecoder().decode([SavedProgress].self, from: data) else {
            return
        }
        saved.removeAll { $0.calendarId == calendarId }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: progressKey)
        }
    }

    func importAllEventsToArchive(
        auth: GoogleAuthService,
        modelContext: ModelContext,
        calendars: [CachedCalendar],   // isEnabled を無視して「取り込み対象」を決めてもOK
        onProgress: @Sendable (Progress) -> Void
    ) async throws {

        try await auth.ensureCalendarScopeGranted()
        let token = try await auth.validAccessToken()

        let now = Date()
        let archiveStart = dateFromYMD(2000, 1, 1)
        let archiveEnd = Calendar.current.date(byAdding: .day, value: 365, to: now) ?? now

        // 半年単位で区切る
        let ranges = splitIntoHalfYearRanges(from: archiveStart, to: archiveEnd)

        var progress = Progress(totalRanges: ranges.count)

        for cal in calendars {
            // キャンセルチェック（カレンダー開始時）
            try Task.checkCancellation()

            progress.calendarId = cal.calendarId
            progress.fetchedRanges = 0
            progress.upserted = 0
            progress.deleted = 0

            // ログ記録開始
            let syncLog = SyncLog(
                syncType: "archive",
                calendarIdHash: SyncLog.hashCalendarId(cal.calendarId)
            )
            modelContext.insert(syncLog)

            var totalRetryResult = RetryResult()

            // 前回の進捗を復元
            let startIndex = loadProgress(for: cal.calendarId) ?? -1
            if startIndex >= 0 {
                progress.fetchedRanges = startIndex + 1
            }
            onProgress(progress)

            do {
                for (index, (timeMin, timeMax)) in ranges.enumerated() {
                    // 既に完了したレンジはスキップ
                    if index <= startIndex {
                        continue
                    }

                    // キャンセルチェック（バッチ開始前）
                    try Task.checkCancellation()

                    progress.fetchedRanges = index + 1
                    onProgress(progress)

                    // フル同期として events.list を期間指定で取得（syncTokenは使わない）
                    let result = try await GoogleCalendarClient.listEvents(
                        accessToken: token,
                        calendarId: cal.calendarId,
                        timeMin: timeMin,
                        timeMax: timeMax,
                        syncToken: nil
                    )

                    // リトライ結果を累積
                    totalRetryResult.retryCount += result.retryResult.retryCount
                    totalRetryResult.totalWaitTime += result.retryResult.totalWaitTime

                    // 取得したイベントをアーカイブに反映
                    let delta = try applyToArchive(
                        events: result.events,
                        calendarId: cal.calendarId,
                        modelContext: modelContext
                    )
                    progress.upserted += delta.upserted
                    progress.deleted += delta.deleted
                    onProgress(progress)

                    // 端末を守るため、バッチごとに保存
                    try modelContext.save()

                    // 進捗を保存（このレンジが完了）
                    saveProgress(calendarId: cal.calendarId, completedRangeIndex: index)

                    // キャンセルチェック（sleep前）
                    try Task.checkCancellation()

                    // やりすぎ防止の小休止（レート制限の一部）
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

                    // キャンセルチェック（sleep後）
                    try Task.checkCancellation()
                }

                // このカレンダーが完了したので進捗をクリア
                clearProgress(for: cal.calendarId)

                // ログ記録（成功）
                syncLog.endTimestamp = Date()
                syncLog.updatedCount = progress.upserted
                syncLog.deletedCount = progress.deleted
                syncLog.had429Retry = totalRetryResult.retryCount > 0
                syncLog.retryCount = totalRetryResult.retryCount
                syncLog.totalWaitTime = totalRetryResult.totalWaitTime
                syncLog.httpStatusCode = 200
                try modelContext.save()

            } catch is CancellationError {
                // ログ記録（キャンセル）
                syncLog.endTimestamp = Date()
                syncLog.updatedCount = progress.upserted
                syncLog.deletedCount = progress.deleted
                syncLog.had429Retry = totalRetryResult.retryCount > 0
                syncLog.retryCount = totalRetryResult.retryCount
                syncLog.totalWaitTime = totalRetryResult.totalWaitTime
                syncLog.errorType = "CancellationError"
                syncLog.errorMessage = "取り込みがキャンセルされました"
                try? modelContext.save()
                throw CancellationError()
            } catch {
                // ログ記録（エラー）
                syncLog.endTimestamp = Date()
                syncLog.updatedCount = progress.upserted
                syncLog.deletedCount = progress.deleted
                syncLog.had429Retry = totalRetryResult.retryCount > 0
                syncLog.retryCount = totalRetryResult.retryCount
                syncLog.totalWaitTime = totalRetryResult.totalWaitTime
                syncLog.errorType = String(describing: type(of: error))
                syncLog.errorMessage = error.localizedDescription
                
                // HTTPステータスコードを取得
                let httpStatusCode = SyncErrorReporter.extractHttpStatusCode(from: error)
                syncLog.httpStatusCode = httpStatusCode
                
                try? modelContext.save()
                
                // Crashlyticsに送信
                SyncErrorReporter.reportSyncFailure(
                    error: error,
                    syncType: "archive",
                    calendarId: cal.calendarId,
                    phase: "long_term",
                    had410Fallback: false,
                    httpStatusCode: httpStatusCode
                )
                
                throw error
            }
        }
    }

    private func applyToArchive(
        events: [GoogleCalendarEvent],
        calendarId: String,
        modelContext: ModelContext
    ) throws -> (upserted: Int, deleted: Int) {

        var upserted = 0
        var deleted = 0

        // 祝日プロバイダー（設定から取得）
        let settings = RelatedMemorySettings.load()
        let holidayProvider = HolidayProviderFactory.provider(for: settings.holidayRegion)

        for e in events {
            let uid = "\(calendarId):\(e.id)"

            // cancelled はアーカイブ側も削除で反映（残すと幽霊になる）
            if e.status == "cancelled" {
                if let existing = fetchArchived(uid: uid, modelContext: modelContext) {
                    modelContext.delete(existing)
                    deleted += 1
                }
                continue
            }

            let dayKey = makeDayKey(e.start)
            let monthDayKey = makeMonthDayKey(e.start)
            let journalId = e.privateProps?["journalId"]

            // 祝日判定
            let holidayId = holidayProvider.holiday(for: e.start)?.holidayId

            if let existing = fetchArchived(uid: uid, modelContext: modelContext) {
                existing.calendarId = calendarId
                existing.eventId = e.id
                existing.title = e.title
                existing.desc = e.description
                existing.start = e.start
                existing.end = e.end
                existing.isAllDay = e.isAllDay
                existing.status = e.status
                existing.updatedAt = e.updated
                existing.startDayKey = dayKey
                existing.startMonthDayKey = monthDayKey
                existing.holidayId = holidayId
                existing.linkedJournalId = journalId
                existing.cachedAt = Date()
                upserted += 1
            } else {
                let archived = ArchivedCalendarEvent(
                    uid: uid,
                    calendarId: calendarId,
                    eventId: e.id,
                    title: e.title,
                    desc: e.description,
                    start: e.start,
                    end: e.end,
                    isAllDay: e.isAllDay,
                    status: e.status,
                    updatedAt: e.updated,
                    startDayKey: dayKey,
                    startMonthDayKey: monthDayKey,
                    holidayId: holidayId,
                    linkedJournalId: journalId
                )
                modelContext.insert(archived)
                upserted += 1
            }
        }

        return (upserted, deleted)
    }

    private func fetchArchived(uid: String, modelContext: ModelContext) -> ArchivedCalendarEvent? {
        let p = #Predicate<ArchivedCalendarEvent> { $0.uid == uid }
        let d = FetchDescriptor(predicate: p)
        return try? modelContext.fetch(d).first
    }

    private func makeDayKey(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return y * 10000 + m * 100 + d
    }

    private func makeMonthDayKey(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        let m = c.month ?? 0
        let d = c.day ?? 0
        return m * 100 + d
    }

    private func dateFromYMD(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    private func splitIntoHalfYearRanges(from start: Date, to end: Date) -> [(Date, Date)] {
        var ranges: [(Date, Date)] = []
        var cursor = start
        let cal = Calendar.current

        while cursor < end {
            let next = cal.date(byAdding: .month, value: 6, to: cursor) ?? end
            let upper = min(next, end)
            ranges.append((cursor, upper))
            cursor = upper
        }
        return ranges
    }
}

