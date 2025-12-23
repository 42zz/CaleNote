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

    // 関連メモリー検索用インデックス
    // オプショナルにして、既存データとの互換性を保つ
    // nilの場合はstartから計算される（computedMonthDayKeyを使用）
    var startMonthDayKey: Int?   // MMDD（例: 1223）
    
    var holidayId: String?       // 祝日ID（例: "JP:NEW_YEAR"）
    
    // startMonthDayKeyがnilの場合にstartから計算するヘルパー
    var computedMonthDayKey: Int {
        if let stored = startMonthDayKey {
            return stored
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: start)
        let m = components.month ?? 0
        let d = components.day ?? 0
        return m * 100 + d
    }

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
        startMonthDayKey: Int? = nil,  // オプショナルに変更
        holidayId: String? = nil,
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
        self.startMonthDayKey = startMonthDayKey
        self.holidayId = holidayId
        self.linkedJournalId = linkedJournalId
        self.cachedAt = cachedAt
    }
}

