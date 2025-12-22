//
//  JournalEntry.swift
//  CaleNote
//
//  Created by Masaya Kawai on 2025/12/20.
//
import Foundation
import SwiftData

@Model
final class JournalEntry {
    // SwiftDataが一意性を面倒見てくれるけど、外部連携が入ると必要になるので用意
    @Attribute(.unique) var id: UUID
    var journalId: UUID

    var title: String?
    var body: String

    // “出来事の日時”。作成日時と分けたいなら別で createdAt を追加する
    var eventDate: Date
    var createdAt: Date
    var updatedAt: Date

    // UI用。最初は String で十分（後で enum や別モデルにしてもよい）
    var colorHex: String
    var iconName: String

    var linkedCalendarId: String?  // 書き込んだカレンダーID（例: "primary"）
    var linkedEventId: String?  // Google側のeventId
    var linkedEventUpdatedAt: Date?

    var needsCalendarSync: Bool  // 同期失敗したらtrue（後で再送用）

    // 競合検知用フィールド
    var hasConflict: Bool = false
    var conflictDetectedAt: Date?
    var conflictRemoteTitle: String?
    var conflictRemoteBody: String?
    var conflictRemoteUpdatedAt: Date?
    var conflictRemoteEventDate: Date?

    init(
        id: UUID = UUID(),
        journalId: UUID = UUID(),
        title: String? = nil,
        body: String,
        eventDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        colorHex: String = "#3B82F6",  // とりあえず青。色設計は後で
        iconName: String = "note.text",
        linkedCalendarId: String? = nil,
        linkedEventId: String? = nil,
        linkedEventUpdatedAt: Date? = nil,
        needsCalendarSync: Bool = false,
        hasConflict: Bool = false,
        conflictDetectedAt: Date? = nil,
        conflictRemoteTitle: String? = nil,
        conflictRemoteBody: String? = nil,
        conflictRemoteUpdatedAt: Date? = nil,
        conflictRemoteEventDate: Date? = nil
    ) {
        self.id = id
        self.journalId = journalId
        self.title = title
        self.body = body
        self.eventDate = eventDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.colorHex = colorHex
        self.iconName = iconName
        self.linkedCalendarId = linkedCalendarId
        self.linkedEventId = linkedEventId
        self.linkedEventUpdatedAt = linkedEventUpdatedAt
        self.needsCalendarSync = needsCalendarSync
        self.hasConflict = hasConflict
        self.conflictDetectedAt = conflictDetectedAt
        self.conflictRemoteTitle = conflictRemoteTitle
        self.conflictRemoteBody = conflictRemoteBody
        self.conflictRemoteUpdatedAt = conflictRemoteUpdatedAt
        self.conflictRemoteEventDate = conflictRemoteEventDate
    }
}
