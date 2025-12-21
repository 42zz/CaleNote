import Foundation
import SwiftData

@MainActor
final class CalendarToJournalSyncService {

  struct ApplyResult {
    var updatedCount: Int = 0
    var unlinkedCount: Int = 0
    var skippedCount: Int = 0
  }

  /// CachedCalendarEvent（差分同期後のキャッシュ）を見て、JournalEntryへ反映する
  func applyFromCachedEvents(
    modelContext: ModelContext,
    calendarId: String? = nil
  ) throws -> ApplyResult {

    var result = ApplyResult()

    // 取得対象（特定カレンダーだけに絞れる）
    let descriptor: FetchDescriptor<CachedCalendarEvent>
    if let calendarId {
      let p = #Predicate<CachedCalendarEvent> { $0.calendarId == calendarId }
      descriptor = FetchDescriptor(predicate: p)
    } else {
      descriptor = FetchDescriptor<CachedCalendarEvent>()
    }

    let cachedEvents = try modelContext.fetch(descriptor)

    // journalId を持つイベントだけ対象
    for ev in cachedEvents {
      guard let journalId = ev.linkedJournalId, !journalId.isEmpty else {
        continue
      }

      // 対応するJournalEntryを探す（UUID文字列で一致）
      guard let entry = fetchJournalEntry(idString: journalId, modelContext: modelContext) else {
        // ジャーナルが無いなら、今回は何もしない（将来: 自動生成もできる）
        result.skippedCount += 1
        continue
      }

      // カレンダーで削除されたイベントなら「リンク解除」だけする
      if ev.status == "cancelled" {
        if entry.linkedEventId != nil {
          entry.linkedEventId = nil
          entry.linkedCalendarId = nil
          entry.linkedEventUpdatedAt = nil
          // ユーザーが望むなら再作成できる余地
          entry.needsCalendarSync = true
          entry.updatedAt = Date()
          result.unlinkedCount += 1
        } else {
          result.skippedCount += 1
        }
        continue
      }

      // Google updatedAt（キャッシュ側）を基準に反映判定
      let calendarUpdatedAt = ev.updatedAt

      // すでに反映済みならスキップ
      if let lastSeen = entry.linkedEventUpdatedAt, lastSeen >= calendarUpdatedAt {
        result.skippedCount += 1
        continue
      }

      // ローカルの更新がカレンダーより新しければ、今回はカレンダー反映をしない
      // （ここが将来「競合」になるポイント。今は安全側に倒してスキップ）
      if entry.updatedAt > calendarUpdatedAt {
        result.skippedCount += 1
        continue
      }

      // 反映（タイトル/本文/日時）
      entry.title = ev.title.isEmpty ? nil : ev.title
      entry.body = ev.desc ?? ""  // descriptionが空なら空文字
      entry.eventDate = ev.start
      entry.updatedAt = Date()

      // リンク情報も補正（カレンダー側でイベントIDが変わるケースは基本ないが保険）
      entry.linkedCalendarId = ev.calendarId
      entry.linkedEventId = ev.eventId
      entry.linkedEventUpdatedAt = calendarUpdatedAt
      entry.needsCalendarSync = false

      result.updatedCount += 1
    }

    try modelContext.save()
    return result
  }

  private func fetchJournalEntry(idString: String, modelContext: ModelContext) -> JournalEntry? {
    guard let uuid = UUID(uuidString: idString) else { return nil }
    let p = #Predicate<JournalEntry> { $0.id == uuid }
    let d = FetchDescriptor(predicate: p)
    return try? modelContext.fetch(d).first
  }
}
