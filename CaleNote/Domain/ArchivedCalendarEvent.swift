import Foundation
import SwiftData

@Model
final class ArchivedCalendarEvent {
    @Attribute(.unique) var uid: String          // "\(calendarId):\(eventId)"
    var calendarId: String
    var eventId: String

    var title: String
    var desc: String?
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var status: String
    var updatedAt: Date

    // アーカイブ検索を軽くするためのインデックス用（YYYYMMDD）
    var startDayKey: Int

    // アプリ紐付け
    var linkedJournalId: String?

    var cachedAt: Date

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
        startDayKey: Int,
        linkedJournalId: String?,
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
        self.startDayKey = startDayKey
        self.linkedJournalId = linkedJournalId
        self.cachedAt = cachedAt
    }
}

