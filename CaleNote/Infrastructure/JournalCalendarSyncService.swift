import Foundation
import SwiftData

@MainActor
final class JournalCalendarSyncService {
  /// ジャーナル1件をGoogleカレンダーへ反映（未紐付けならinsert、紐付け済みならupdate）
  func syncOne(
    entry: JournalEntry,
    targetCalendarId: String,
    auth: GoogleAuthService,
    modelContext: ModelContext
  ) async throws {

    try await auth.ensureCalendarScopeGranted()
    let token = try await auth.validAccessToken()

    // ログ記録開始
    let syncLog = SyncLog(
      syncType: "journal_push",
      calendarIdHash: SyncLog.hashCalendarId(targetCalendarId)
    )
    modelContext.insert(syncLog)

    do {
      // 予定の長さ（とりあえず1時間）。後でUIで変えればいい
      let start = entry.eventDate
      let end =
        Calendar.current.date(byAdding: .minute, value: 60, to: start)
        ?? start.addingTimeInterval(3600)

      let title = (entry.title?.isEmpty == false) ? entry.title! : "ジャーナル"
      let description = entry.body

      let appPrivateProperties: [String: String] = [
        "app": "calenote",
        "schema": "1",
        "journalId": entry.id.uuidString,
      ]

      var retryResult = RetryResult()

      if let calendarId = entry.linkedCalendarId,
        let eventId = entry.linkedEventId,
        calendarId == targetCalendarId
      {

        let result = try await GoogleCalendarClient.updateEvent(
          accessToken: token,
          calendarId: calendarId,
          eventId: eventId,
          title: title,
          description: description,
          start: start,
          end: end,
          appPrivateProperties: appPrivateProperties
        )

        retryResult = result.retryResult

        // ローカル側の紐付けは維持、失敗フラグを落とす
        entry.needsCalendarSync = false
        entry.updatedAt = Date()

        // ついでにイベントキャッシュも即時更新（同期を待たない）
        upsertCachedEvent(from: result.event, calendarId: calendarId, modelContext: modelContext)

      } else {
        let result = try await GoogleCalendarClient.insertEvent(
          accessToken: token,
          calendarId: targetCalendarId,
          title: title,
          description: description,
          start: start,
          end: end,
          appPrivateProperties: appPrivateProperties
        )

        retryResult = result.retryResult

        entry.linkedCalendarId = targetCalendarId
        entry.linkedEventId = result.event.id
        entry.needsCalendarSync = false
        entry.updatedAt = Date()

        upsertCachedEvent(from: result.event, calendarId: targetCalendarId, modelContext: modelContext)
      }

      // ログ記録（成功）
      syncLog.endTimestamp = Date()
      syncLog.updatedCount = 1  // ジャーナル1件を同期
      syncLog.had429Retry = retryResult.retryCount > 0
      syncLog.retryCount = retryResult.retryCount
      syncLog.totalWaitTime = retryResult.totalWaitTime
      syncLog.httpStatusCode = 200

      try modelContext.save()
    } catch {
      // ログ記録（エラー）
      syncLog.endTimestamp = Date()
      syncLog.errorType = String(describing: type(of: error))
      syncLog.errorMessage = error.localizedDescription
      try? modelContext.save()
      throw error
    }
  }

  private func upsertCachedEvent(
    from event: GoogleCalendarEvent, calendarId: String, modelContext: ModelContext
  ) {
    let uid = "\(calendarId):\(event.id)"
    let predicate = #Predicate<CachedCalendarEvent> { $0.uid == uid }
    let descriptor = FetchDescriptor(predicate: predicate)
    let existing = try? modelContext.fetch(descriptor).first

    if let cached = existing {
      cached.title = event.title
      cached.desc = event.description
      cached.start = event.start
      cached.end = event.end
      cached.isAllDay = event.isAllDay
      cached.status = event.status
      cached.updatedAt = event.updated
      cached.cachedAt = Date()
      cached.linkedJournalId = event.privateProps?["journalId"]
    } else {
      let cached = CachedCalendarEvent(
        uid: uid,
        calendarId: calendarId,
        eventId: event.id,
        linkedJournalId: event.privateProps?["journalId"],
        title: event.title,
        desc: event.description,
        start: event.start,
        end: event.end,
        isAllDay: event.isAllDay,
        status: event.status,
        updatedAt: event.updated
      )
      modelContext.insert(cached)
    }
  }
  func deleteRemoteIfLinked(
    entry: JournalEntry,
    auth: GoogleAuthService,
    modelContext: ModelContext
  ) async throws {
    guard let calendarId = entry.linkedCalendarId,
      let eventId = entry.linkedEventId
    else {
      return
    }

    try await auth.ensureCalendarScopeGranted()
    let token = try await auth.validAccessToken()

    _ = try await GoogleCalendarClient.deleteEvent(
      accessToken: token,
      calendarId: calendarId,
      eventId: eventId
    )

    // ローカルのカレンダーキャッシュも即時に消す（次の同期を待たない）
    let uid = "\(calendarId):\(eventId)"
    let p = #Predicate<CachedCalendarEvent> { $0.uid == uid }
    let d = FetchDescriptor(predicate: p)
    if let cached = try? modelContext.fetch(d).first {
      modelContext.delete(cached)
    }

    try modelContext.save()
  }
}
