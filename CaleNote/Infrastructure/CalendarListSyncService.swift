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

    // ログ記録開始
    let syncLog = SyncLog(
      syncType: "calendar_list",
      calendarIdHash: nil  // カレンダーリスト全体の取得なので個別IDなし
    )
    modelContext.insert(syncLog)

    do {
      let result = try await GoogleCalendarClient.listCalendars(accessToken: token)

      // 既存を取得して辞書化
      let existing = (try? modelContext.fetch(FetchDescriptor<CachedCalendar>())) ?? []
      var dict = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarId, $0) })

      var updatedCount = 0

      for item in result.calendars {
        if let c = dict[item.id] {
          c.summary = item.summary
          c.isPrimary = item.primary
          c.googleColorId = item.colorId
          // iconNameが空の場合はデフォルト値を設定（既存データのマイグレーション）
          if c.iconName.isEmpty {
            c.iconName = "calendar"
          }
          c.updatedAt = Date()

          // 初回だけ primary を自動ONにする（好み）
          if c.isPrimary && c.isEnabled == false
            && existing.first(where: { $0.calendarId == c.calendarId }) == nil
          {
            c.isEnabled = true
          }
          updatedCount += 1
        } else {
          let new = CachedCalendar(
            calendarId: item.id,
            summary: item.summary,
            isPrimary: item.primary,
            googleColorId: item.colorId,
            userColorHex: "#3B82F6",
            iconName: "calendar",  // デフォルト値
            isEnabled: item.primary,  // 初回はprimaryだけON
            updatedAt: Date()
          )
          modelContext.insert(new)
          dict[item.id] = new
          updatedCount += 1
        }
      }

      // ログ記録（成功）
      syncLog.endTimestamp = Date()
      syncLog.updatedCount = updatedCount
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
      try? modelContext.save()
      throw error
    }
  }
}
