//
//  CalendarModels.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation

// MARK: - Calendar Event

/// Google Calendar イベント
struct CalendarEvent: Codable {
    let id: String?
    let status: String?
    let summary: String?
    let description: String?
    let start: EventDateTime?
    let end: EventDateTime?
    let created: String?
    let updated: String?
    let etag: String?
    let extendedProperties: ExtendedProperties?
    let recurrence: [String]?
    let recurringEventId: String?
    let originalStartTime: EventDateTime?

    struct EventDateTime: Codable {
        let date: String?
        let dateTime: String?
        let timeZone: String?
    }

    struct ExtendedProperties: Codable {
        let `private`: [String: String]?
        let shared: [String: String]?
    }
}

// MARK: - Calendar List

/// Google Calendar リスト
struct CalendarList: Codable {
    let kind: String?
    let etag: String?
    let nextPageToken: String?
    let nextSyncToken: String?
    let items: [CalendarListEntry]?
}

/// カレンダーリストのエントリ
struct CalendarListEntry: Codable {
    let id: String
    let summary: String?
    let description: String?
    let backgroundColor: String?
    let foregroundColor: String?
    let accessRole: String?
    let selected: Bool?
    let primary: Bool?
}

// MARK: - Event List Response

/// イベントリストのレスポンス
struct EventListResponse: Codable {
    let kind: String?
    let etag: String?
    let summary: String?
    let updated: String?
    let timeZone: String?
    let accessRole: String?
    let nextPageToken: String?
    let nextSyncToken: String?
    let items: [CalendarEvent]?
}

// MARK: - Error Response

/// Google API エラーレスポンス
struct GoogleAPIErrorResponse: Codable {
    let error: GoogleAPIError

    struct GoogleAPIError: Codable {
        let code: Int
        let message: String
        let errors: [ErrorDetail]?
        let status: String?

        struct ErrorDetail: Codable {
            let domain: String?
            let reason: String?
            let message: String?
        }
    }
}
