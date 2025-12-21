import Foundation
import SwiftData

@Model
final class CachedCalendarEvent {
  @Attribute(.unique) var uid: String  // "calendarId:eventId" みたいにユニークにする
  var calendarId: String  // まずは "primary" 固定でOK
  var eventId: String

  var title: String
  var desc: String?
  var start: Date
  var end: Date?
  var isAllDay: Bool
  var status: String  // confirmed / cancelled とか（削除反映に使う）

  var updatedAt: Date  // APIのupdated（取れるなら）
  var cachedAt: Date  // 端末に保存した時刻

  init(
    uid: String,
    calendarId: String,
    eventId: String,
    title: String,
    desc: String?,
    start: Date,
    end: Date?,
    isAllDay: Bool,
    status: String,
    updatedAt: Date,
    cachedAt: Date = Date()
  ) {
    self.uid = uid
    self.calendarId = calendarId
    self.eventId = eventId
    self.title = title
    self.desc = desc
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.status = status
    self.updatedAt = updatedAt
    self.cachedAt = cachedAt
  }
}
