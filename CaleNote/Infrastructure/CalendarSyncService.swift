import Foundation
import SwiftData

@MainActor
final class CalendarSyncService {
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

    do {
      let result = try await GoogleCalendarClient.listEvents(
        accessToken: token,
        calendarId: calendarId,
        timeMin: existingSyncToken == nil ? initialTimeMin : nil,
        timeMax: existingSyncToken == nil ? initialTimeMax : nil,
        syncToken: existingSyncToken
      )

      applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }
      try modelContext.save()

    } catch CalendarSyncError.syncTokenExpired {
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

      applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }
      try modelContext.save()
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

    do {
      let result = try await GoogleCalendarClient.listEvents(
        accessToken: token,
        calendarId: calendarId,
        timeMin: existingSyncToken == nil ? initialTimeMin : nil,
        timeMax: existingSyncToken == nil ? initialTimeMax : nil,
        syncToken: existingSyncToken
      )

      applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }

      try modelContext.save()

    } catch CalendarSyncError.syncTokenExpired {
      // 公式推奨: ストレージをクリアしてフル同期やり直し :contentReference[oaicite:4]{index=4}
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

      applyToCache(events: result.events, calendarId: calendarId, modelContext: modelContext)

      if let next = result.nextSyncToken {
        CalendarSyncState.saveSyncToken(next, calendarId: calendarId)
      }

      try modelContext.save()
    }
  }

  private func applyToCache(
    events: [GoogleCalendarEvent], calendarId: String, modelContext: ModelContext
  ) {
    for e in events {
      let uid = "\(calendarId):\(e.id)"

      // 削除（cancelled）はローカルから消す（増分同期では削除も返る）:contentReference[oaicite:5]{index=5}
      if e.status == "cancelled" {
        deleteCached(uid: uid, modelContext: modelContext)
        continue
      }

      if let cached = fetchCached(uid: uid, modelContext: modelContext) {
        cached.title = e.title
        cached.desc = e.description
        cached.start = e.start
        cached.end = e.end
        cached.isAllDay = e.isAllDay
        cached.status = e.status
        cached.updatedAt = e.updated
        cached.cachedAt = Date()
      } else {
        let cached = CachedCalendarEvent(
          uid: uid,
          calendarId: calendarId,
          eventId: e.id,
          title: e.title,
          desc: e.description,
          start: e.start,
          end: e.end,
          isAllDay: e.isAllDay,
          status: e.status,
          updatedAt: e.updated
        )
        modelContext.insert(cached)
      }
    }
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
}
