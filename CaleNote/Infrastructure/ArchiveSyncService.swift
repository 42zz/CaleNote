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
            progress.calendarId = cal.calendarId
            progress.fetchedRanges = 0
            progress.upserted = 0
            progress.deleted = 0
            onProgress(progress)

            for (timeMin, timeMax) in ranges {
                progress.fetchedRanges += 1
                onProgress(progress)

                // フル同期として events.list を期間指定で取得（syncTokenは使わない）
                let result = try await GoogleCalendarClient.listEvents(
                    accessToken: token,
                    calendarId: cal.calendarId,
                    timeMin: timeMin,
                    timeMax: timeMax,
                    syncToken: nil
                )

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

                // やりすぎ防止の小休止（レート制限の一部）
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
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
            let journalId = e.privateProps?["journalId"]

            if let existing = fetchArchived(uid: uid, modelContext: modelContext) {
                existing.title = e.title
                existing.desc = e.description
                existing.start = e.start
                existing.end = e.end
                existing.isAllDay = e.isAllDay
                existing.status = e.status
                existing.updatedAt = e.updated
                existing.startDayKey = dayKey
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

