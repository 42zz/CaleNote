//
//  GoogleCalendarClient.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation
import OSLog

/// Google Calendar API v3 クライアント
@MainActor
final class GoogleCalendarClient {
    // MARK: - Constants

    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "GoogleCalendarAPI")

    // MARK: - Dependencies

    private let authService: GoogleAuthService
    private let urlSession: URLSession

    // MARK: - Rate Limiting

    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 0.1 // 100ms between requests

    // MARK: - Initialization

    init(
        authService: GoogleAuthService = .shared,
        urlSession: URLSession = .shared
    ) {
        self.authService = authService
        self.urlSession = urlSession
    }

    // MARK: - Calendar List

    /// カレンダーリストを取得
    /// - Parameters:
    ///   - pageToken: ページトークン（オプション）
    ///   - syncToken: 同期トークン（オプション）
    /// - Returns: カレンダーリスト
    /// - Throws: API エラー
    func getCalendarList(
        pageToken: String? = nil,
        syncToken: String? = nil
    ) async throws -> CalendarList {
        let endpoint = "/users/me/calendarList"
        var queryItems: [URLQueryItem] = []

        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        if let syncToken = syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        }

        let response: CalendarList = try await executeRequest(
            endpoint: endpoint,
            method: "GET",
            queryItems: queryItems
        )

        return response
    }

    // MARK: - Events CRUD

    /// イベントを作成
    /// - Parameters:
    ///   - calendarId: カレンダー ID
    ///   - event: 作成するイベント
    /// - Returns: 作成されたイベント
    /// - Throws: API エラー
    func createEvent(
        calendarId: String,
        event: CalendarEvent
    ) async throws -> CalendarEvent {
        let endpoint = "/calendars/\(calendarId)/events"

        let createdEvent: CalendarEvent = try await executeRequest(
            endpoint: endpoint,
            method: "POST",
            body: event
        )

        logger.info("Created event: \(createdEvent.id ?? "unknown")")
        return createdEvent
    }

    /// イベントを取得
    /// - Parameters:
    ///   - calendarId: カレンダー ID
    ///   - eventId: イベント ID
    /// - Returns: イベント
    /// - Throws: API エラー
    func getEvent(
        calendarId: String,
        eventId: String
    ) async throws -> CalendarEvent {
        let endpoint = "/calendars/\(calendarId)/events/\(eventId)"

        let event: CalendarEvent = try await executeRequest(
            endpoint: endpoint,
            method: "GET"
        )

        return event
    }

    /// イベントリストを取得
    /// - Parameters:
    ///   - calendarId: カレンダー ID
    ///   - timeMin: 取得開始時刻（ISO 8601）
    ///   - timeMax: 取得終了時刻（ISO 8601）
    ///   - pageToken: ページトークン（オプション）
    ///   - syncToken: 同期トークン（オプション）
    ///   - maxResults: 最大結果数（デフォルト: 250）
    /// - Returns: イベントリストレスポンス
    /// - Throws: API エラー
    func listEvents(
        calendarId: String,
        timeMin: String? = nil,
        timeMax: String? = nil,
        pageToken: String? = nil,
        syncToken: String? = nil,
        maxResults: Int = 250
    ) async throws -> EventListResponse {
        let endpoint = "/calendars/\(calendarId)/events"
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        if let timeMin = timeMin {
            queryItems.append(URLQueryItem(name: "timeMin", value: timeMin))
        }
        if let timeMax = timeMax {
            queryItems.append(URLQueryItem(name: "timeMax", value: timeMax))
        }
        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        if let syncToken = syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        }

        let response: EventListResponse = try await executeRequest(
            endpoint: endpoint,
            method: "GET",
            queryItems: queryItems
        )

        return response
    }

    /// イベントを更新
    /// - Parameters:
    ///   - calendarId: カレンダー ID
    ///   - eventId: イベント ID
    ///   - event: 更新するイベント
    /// - Returns: 更新されたイベント
    /// - Throws: API エラー
    func updateEvent(
        calendarId: String,
        eventId: String,
        event: CalendarEvent
    ) async throws -> CalendarEvent {
        let endpoint = "/calendars/\(calendarId)/events/\(eventId)"

        let updatedEvent: CalendarEvent = try await executeRequest(
            endpoint: endpoint,
            method: "PUT",
            body: event
        )

        logger.info("Updated event: \(eventId)")
        return updatedEvent
    }

    /// イベントを削除
    /// - Parameters:
    ///   - calendarId: カレンダー ID
    ///   - eventId: イベント ID
    /// - Throws: API エラー
    func deleteEvent(
        calendarId: String,
        eventId: String
    ) async throws {
        let endpoint = "/calendars/\(calendarId)/events/\(eventId)"

        let _: EmptyResponse = try await executeRequest(
            endpoint: endpoint,
            method: "DELETE"
        )

        logger.info("Deleted event: \(eventId)")
    }

    // MARK: - Request Execution

    /// API リクエストを実行
    /// - Parameters:
    ///   - endpoint: エンドポイント
    ///   - method: HTTP メソッド
    ///   - queryItems: クエリパラメータ
    ///   - body: リクエストボディ
    /// - Returns: レスポンス
    /// - Throws: API エラー
    private func executeRequest<T: Decodable>(
        endpoint: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws -> T {
        // レート制限チェック
        try await enforceRateLimit()

        // アクセストークン取得
        let accessToken = try await authService.getAccessToken()

        // URL 構築
        var urlComponents = URLComponents(string: baseURL + endpoint)!
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        guard let url = urlComponents.url else {
            throw CaleNoteError.apiError(.invalidResponse)
        }

        // リクエスト構築
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // ボディ設定
        if let body = body {
            request.httpBody = try encodeBody(body)
        }

        // リトライロジック付きで実行
        return try await RetryExecutor.execute(policy: .default) {
            try await self.performRequest(request)
        }
    }

    /// 実際のリクエスト実行
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CaleNoteError.apiError(.invalidResponse)
        }

        // ステータスコード処理
        switch httpResponse.statusCode {
        case 200...299:
            // 成功
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                logger.error("Decoding error: \(error.localizedDescription)")
                throw CaleNoteError.apiError(.decodingError(error))
            }

        case 401:
            throw CaleNoteError.apiError(.unauthorized)

        case 403:
            throw CaleNoteError.apiError(.forbidden)

        case 404:
            throw CaleNoteError.apiError(.notFound)

        case 410:
            // syncToken が失効
            throw CaleNoteError.apiError(.tokenExpired)

        case 429:
            // レート制限
            throw CaleNoteError.apiError(.rateLimited)

        case 500...599:
            throw CaleNoteError.apiError(.serverError(httpResponse.statusCode))

        default:
            // エラーレスポンスをパース
            if let errorResponse = try? JSONDecoder().decode(GoogleAPIErrorResponse.self, from: data) {
                throw CaleNoteError.apiError(.other(
                    errorResponse.error.code,
                    errorResponse.error.message
                ))
            }
            throw CaleNoteError.apiError(.other(httpResponse.statusCode, nil))
        }
    }

    /// レート制限を適用
    private func enforceRateLimit() async throws {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumRequestInterval {
                let delay = minimumRequestInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    /// Encodable な値を JSON Data にエンコード
    private func encodeBody(_ body: any Encodable) throws -> Data {
        let encoder = JSONEncoder()

        // type-erased encoding
        if let calendarEvent = body as? CalendarEvent {
            return try encoder.encode(calendarEvent)
        }

        // 他の型も必要に応じて追加
        throw CaleNoteError.apiError(.other(0, "Unsupported body type"))
    }
}

// MARK: - Empty Response

/// 空のレスポンス（DELETE 用）
private struct EmptyResponse: Decodable {
    init() {}
}

// MARK: - Helper Extensions

extension GoogleCalendarClient {
    /// syncToken を使用してイベントを取得（差分同期）
    /// - Parameters:
    ///   - calendarId: カレンダー ID
    ///   - syncToken: 同期トークン
    /// - Returns: イベントリストレスポンス
    /// - Throws: API エラー（410 の場合は syncToken が失効）
    func listEventsSince(
        calendarId: String,
        syncToken: String
    ) async throws -> EventListResponse {
        do {
            return try await listEvents(
                calendarId: calendarId,
                syncToken: syncToken
            )
        } catch CaleNoteError.apiError(.tokenExpired) {
            // syncToken が失効した場合は再スロー
            logger.warning("SyncToken expired for calendar: \(calendarId)")
            throw CaleNoteError.apiError(.tokenExpired)
        }
    }

    /// ISO 8601 形式の日時文字列を生成
    /// - Parameter date: Date
    /// - Returns: ISO 8601 文字列
    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
