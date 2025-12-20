import Foundation

enum TimelineItemKind {
  case journal
  case calendar
}

struct TimelineItem: Identifiable {
  let id: String  // 種別込みで一意
  let kind: TimelineItemKind

  let title: String
  let body: String?
  let date: Date  // 並び替え・セクション用
  let sourceId: String  // JournalEntry.id / CalendarEvent.id
}
