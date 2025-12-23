import Foundation
import SwiftData

@MainActor
final class CalendarSyncService {

  struct SyncResult {
    var updatedCount: Int = 0
    var deletedCount: Int = 0
  }

  func syncEnabledCalendars(
    auth: GoogleAuthService,
    modelContext: ModelContext,
    calendars: [CachedCalendar],
    initialTimeMin: Date,
    initialTimeMax: Date
  ) async throws {

    let enabled = calendars.filter { $0.isEnabled }
    if enabled.isEmpty { return }

    for cal in enabled {
      try await syncOneCalendar(
        auth: auth,
        modelContext: modelContext,
        calendarId: cal.calendarId,
        initialTimeMin: initialTimeMin,
        initialTimeMax: initialTimeMax
      )
    }
  }

  func syncOneCalendar(
    auth: GoogleAuthService,
    modelContext: ModelContext,
    calendarId: String,
    initialTimeMin: Date,
    initialTimeMax: Date
  ) async throws {

    try await auth.ensureCalendarScopeGranted()
    let token = try await auth.validAccessToken()

    let existingSyncToken = CalendarSyncState.loadSyncToken(calendarId: calendarId)
    let isIncremental = existingSyncToken != nil

    // ログ記録開始
    let syncLog = SyncLog(
      syncType: isIncremental ? "incremental" : "full",
      calendarIdHash: SyncLog.hashCalendarId(calendarId)
    )
    modelContext.insert(syncLog)

    var had410Fallback = false

    do {
      let result = try await GoogleCalendarClient.listEvents(
        accessToken: token,
        calendarId: calendarId,
        timeMin: existingSyncToken == nil ? initialTimeMin : nil,
        timeMax: existingSyncToken == nil ? initialTimeMax : nil,
        syncToken: existingSyncToken
      )

      let counts = applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }

      // ログ記録（成功）
      syncLog.endTimestamp = Date()
      syncLog.updatedCount = counts.updatedCount
      syncLog.deletedCount = counts.deletedCount
      syncLog.had410Fallback = had410Fallback
      syncLog.had429Retry = result.retryResult.retryCount > 0
      syncLog.retryCount = result.retryResult.retryCount
      syncLog.totalWaitTime = result.retryResult.totalWaitTime
      syncLog.httpStatusCode = 200

      try modelContext.save()

    } catch CalendarSyncError.syncTokenExpired {
      had410Fallback = true

      clearCache(calendarId: calendarId, modelContext: modelContext)
      CalendarSyncState.saveSyncToken(nil, calendarId: calendarId)
      try modelContext.save()

      let result = try await GoogleCalendarClient.listEvents(
        accessToken: token,
        calendarId: calendarId,
        timeMin: initialTimeMin,
        timeMax: initialTimeMax,
        syncToken: nil
      )

      let counts = applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }

      // ログ記録（410フォールバック後成功）
      syncLog.syncType = "full"  // 410エラー後はフル同期に変更
      syncLog.endTimestamp = Date()
      syncLog.updatedCount = counts.updatedCount
      syncLog.deletedCount = counts.deletedCount
      syncLog.had410Fallback = true
      syncLog.had429Retry = result.retryResult.retryCount > 0
      syncLog.retryCount = result.retryResult.retryCount
      syncLog.totalWaitTime = result.retryResult.totalWaitTime
      syncLog.httpStatusCode = 200

      try modelContext.save()
    } catch {
      // ログ記録（エラー）
      syncLog.endTimestamp = Date()
      syncLog.errorType = String(describing: type(of: error))
      syncLog.errorMessage = error.localizedDescription
      
      // HTTPステータスコードを取得
      let httpStatusCode = SyncErrorReporter.extractHttpStatusCode(from: error)
      syncLog.httpStatusCode = httpStatusCode
      
      try? modelContext.save()
      
      // Crashlyticsに送信
      SyncErrorReporter.reportSyncFailure(
        error: error,
        syncType: syncLog.syncType,
        calendarId: calendarId,
        phase: "short_term",
        had410Fallback: had410Fallback,
        httpStatusCode: httpStatusCode
      )
      
      throw error
    }
  }

  func syncPrimaryCalendar(
    auth: GoogleAuthService,
    modelContext: ModelContext,
    initialTimeMin: Date,
    initialTimeMax: Date
  ) async throws {

    try await auth.ensureCalendarScopeGranted()
    let token = try await auth.validAccessToken()

    let calendarId = "primary"
    let existingSyncToken = CalendarSyncState.loadSyncToken(calendarId: calendarId)
    let isIncremental = existingSyncToken != nil

    // ログ記録開始
    let syncLog = SyncLog(
      syncType: isIncremental ? "incremental" : "full",
      calendarIdHash: SyncLog.hashCalendarId(calendarId)
    )
    modelContext.insert(syncLog)

    var had410Fallback = false

    do {
      let result = try await GoogleCalendarClient.listEvents(
        accessToken: token,
        calendarId: calendarId,
        timeMin: existingSyncToken == nil ? initialTimeMin : nil,
        timeMax: existingSyncToken == nil ? initialTimeMax : nil,
        syncToken: existingSyncToken
      )

      let counts = applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }

      // ログ記録（成功）
      syncLog.endTimestamp = Date()
      syncLog.updatedCount = counts.updatedCount
      syncLog.deletedCount = counts.deletedCount
      syncLog.had410Fallback = had410Fallback
      syncLog.had429Retry = result.retryResult.retryCount > 0
      syncLog.retryCount = result.retryResult.retryCount
      syncLog.totalWaitTime = result.retryResult.totalWaitTime
      syncLog.httpStatusCode = 200

      try modelContext.save()

    } catch CalendarSyncError.syncTokenExpired {
      had410Fallback = true

      // 公式推奨: ストレージをクリアしてフル同期やり直し
      clearCache(calendarId: calendarId, modelContext: modelContext)
      CalendarSyncState.saveSyncToken(nil, calendarId: calendarId)
      try modelContext.save()

      // すぐフル同期
      let result = try await GoogleCalendarClient.listEvents(
        accessToken: token,
        calendarId: calendarId,
        timeMin: initialTimeMin,
        timeMax: initialTimeMax,
        syncToken: nil
      )

      let counts = applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }

      // ログ記録（410フォールバック後成功）
      syncLog.syncType = "full"  // 410エラー後はフル同期に変更
      syncLog.endTimestamp = Date()
      syncLog.updatedCount = counts.updatedCount
      syncLog.deletedCount = counts.deletedCount
      syncLog.had410Fallback = true
      syncLog.had429Retry = result.retryResult.retryCount > 0
      syncLog.retryCount = result.retryResult.retryCount
      syncLog.totalWaitTime = result.retryResult.totalWaitTime
      syncLog.httpStatusCode = 200

      try modelContext.save()
    } catch {
      // ログ記録（エラー）
      syncLog.endTimestamp = Date()
      syncLog.errorType = String(describing: type(of: error))
      syncLog.errorMessage = error.localizedDescription
      
      // HTTPステータスコードを取得
      let httpStatusCode = SyncErrorReporter.extractHttpStatusCode(from: error)
      syncLog.httpStatusCode = httpStatusCode
      
      try? modelContext.save()
      
      // Crashlyticsに送信
      SyncErrorReporter.reportSyncFailure(
        error: error,
        syncType: syncLog.syncType,
        calendarId: calendarId,
        phase: "short_term",
        had410Fallback: had410Fallback,
        httpStatusCode: httpStatusCode
      )
      
      throw error
    }
  }

  private func applyToCache(
    events: [GoogleCalendarEvent], calendarId: String, modelContext: ModelContext
  ) -> SyncResult {
    var result = SyncResult()

    for e in events {
      let uid = "\(calendarId):\(e.id)"

      if e.status == "cancelled" {
        // 1) まずジャーナルを削除（アプリが作ったイベントなら journalId が入っている）
        if let journalId = e.privateProps?["journalId"] {
          deleteJournalIfExists(journalId: journalId, modelContext: modelContext)
        }

        // 2) キャッシュも消す（短期・長期両方）
        deleteCached(uid: uid, modelContext: modelContext)
        deleteArchived(uid: uid, modelContext: modelContext)
        result.deletedCount += 1
        print("cancelled: \(uid) journalId=\(e.privateProps?["journalId"] ?? "nil")")
        continue
      }

      let journalId = e.privateProps?["journalId"]

      // 短期キャッシュの更新
      if let cached = fetchCached(uid: uid, modelContext: modelContext) {
        cached.title = e.title
        cached.desc = e.description
        cached.start = e.start
        cached.end = e.end
        cached.isAllDay = e.isAllDay
        cached.status = e.status
        cached.updatedAt = e.updated
        cached.cachedAt = Date()
        cached.linkedJournalId = journalId
        result.updatedCount += 1
      } else {
        let cached = CachedCalendarEvent(
          uid: uid,
          calendarId: calendarId,
          eventId: e.id,
          linkedJournalId: journalId,
          title: e.title,
          desc: e.description,
          start: e.start,
          end: e.end,
          isAllDay: e.isAllDay,
          status: e.status,
          updatedAt: e.updated,
        )
        modelContext.insert(cached)
        result.updatedCount += 1
      }

      // 長期キャッシュも同時に更新（存在する場合のみ）
      updateArchivedIfExists(
        uid: uid,
        calendarId: calendarId,
        eventId: e.id,
        journalId: journalId,
        event: e,
        modelContext: modelContext
      )
    }

    return result
  }

  private func fetchCached(uid: String, modelContext: ModelContext) -> CachedCalendarEvent? {
    let predicate = #Predicate<CachedCalendarEvent> { $0.uid == uid }
    let descriptor = FetchDescriptor(predicate: predicate)
    return try? modelContext.fetch(descriptor).first
  }

  private func deleteCached(uid: String, modelContext: ModelContext) {
    let predicate = #Predicate<CachedCalendarEvent> { $0.uid == uid }
    let descriptor = FetchDescriptor(predicate: predicate)
    if let target = try? modelContext.fetch(descriptor).first {
      modelContext.delete(target)
    }
  }

  private func clearCache(calendarId: String, modelContext: ModelContext) {
    let predicate = #Predicate<CachedCalendarEvent> { $0.calendarId == calendarId }
    let descriptor = FetchDescriptor(predicate: predicate)
    if let all = try? modelContext.fetch(descriptor) {
      for e in all { modelContext.delete(e) }
    }
  }
  private func deleteJournalIfExists(journalId: String, modelContext: ModelContext) {
    guard let uuid = UUID(uuidString: journalId) else { return }

    let p = #Predicate<JournalEntry> { $0.id == uuid }
    let d = FetchDescriptor(predicate: p)

    if let entry = try? modelContext.fetch(d).first {
      modelContext.delete(entry)
    }
  }

  private func deleteArchived(uid: String, modelContext: ModelContext) {
    let predicate = #Predicate<ArchivedCalendarEvent> { $0.uid == uid }
    let descriptor = FetchDescriptor(predicate: predicate)
    if let target = try? modelContext.fetch(descriptor).first {
      modelContext.delete(target)
    }
  }

  private func updateArchivedIfExists(
    uid: String,
    calendarId: String,
    eventId: String,
    journalId: String?,
    event: GoogleCalendarEvent,
    modelContext: ModelContext
  ) {
    let predicate = #Predicate<ArchivedCalendarEvent> { $0.uid == uid }
    let descriptor = FetchDescriptor(predicate: predicate)

    if let archived = try? modelContext.fetch(descriptor).first {
      // 長期キャッシュが存在する場合は更新
      archived.title = event.title
      archived.desc = event.description
      archived.start = event.start
      archived.end = event.end
      archived.isAllDay = event.isAllDay
      archived.status = event.status
      archived.updatedAt = event.updated
      archived.cachedAt = Date()
      archived.linkedJournalId = journalId

      // startDayKeyも更新（日付が変更された可能性があるため）
      let calendar = Calendar.current
      let components = calendar.dateComponents([.year, .month, .day], from: event.start)
      if let year = components.year, let month = components.month, let day = components.day {
        archived.startDayKey = year * 10000 + month * 100 + day
      }
    }
  }

}
