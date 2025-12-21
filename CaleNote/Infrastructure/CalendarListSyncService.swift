import Foundation
import SwiftData

@MainActor
final class CalendarListSyncService {
  func syncCalendarList(
    auth: GoogleAuthService,
    modelContext: ModelContext
  ) async throws {

    try await auth.ensureCalendarScopeGranted()
    let token = try await auth.validAccessToken()

    let remote = try await GoogleCalendarClient.listCalendars(accessToken: token)

    // 既存を取得して辞書化
    let existing = (try? modelContext.fetch(FetchDescriptor<CachedCalendar>())) ?? []
    var dict = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarId, $0) })

    for item in remote {
      if let c = dict[item.id] {
        c.summary = item.summary
        c.isPrimary = item.primary
        c.googleColorId = item.colorId
        c.updatedAt = Date()

        // 初回だけ primary を自動ONにする（好み）
        if c.isPrimary && c.isEnabled == false
          && existing.first(where: { $0.calendarId == c.calendarId }) == nil
        {
          c.isEnabled = true
        }
      } else {
        let new = CachedCalendar(
          calendarId: item.id,
          summary: item.summary,
          isPrimary: item.primary,
          googleColorId: item.colorId,
          userColorHex: "#3B82F6",
          isEnabled: item.primary,  // 初回はprimaryだけON
          updatedAt: Date()
        )
        modelContext.insert(new)
        dict[item.id] = new
      }
    }

    try modelContext.save()
  }
}
