import Foundation

struct GoogleCalendarEvent: Identifiable {
  let id: String
  let title: String
  let start: Date
  let end: Date?
  let isAllDay: Bool
  let description: String?
  let status: String
  let updated: Date
}

enum GoogleCalendarClient {

  struct ListResult {
    let events: [GoogleCalendarEvent]
    let nextSyncToken: String?
  }

  static func listEvents(
    accessToken: String,
    calendarId: String,
    timeMin: Date?,
    timeMax: Date?,
    syncToken: String?
  ) async throws -> ListResult {

    var all: [GoogleCalendarEvent] = []
    var pageToken: String? = nil
    var newestSyncToken: String? = nil

    repeat {
      var components = URLComponents(
        string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")!
      let iso = ISO8601DateFormatter()

      var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "singleEvents", value: "true"),
        URLQueryItem(name: "maxResults", value: "2500"),
        URLQueryItem(
          name: "fields",
          value:
            "items(id,summary,description,start(dateTime,date),end(dateTime,date),status,updated),nextSyncToken,nextPageToken"
        ),
      ]

      // 初回同期（timeMin/timeMaxあり）か、増分同期（syncTokenあり）か
      if let syncToken {
        queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
      } else {
        if let timeMin {
          queryItems.append(URLQueryItem(name: "timeMin", value: iso.string(from: timeMin)))
        }
        if let timeMax {
          queryItems.append(URLQueryItem(name: "timeMax", value: iso.string(from: timeMax)))
        }
        queryItems.append(URLQueryItem(name: "orderBy", value: "startTime"))
      }

      if let pageToken {
        queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
      }

      components.queryItems = queryItems

      var request = URLRequest(url: components.url!)
      request.httpMethod = "GET"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw NSError(
          domain: "GoogleCalendarClient", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "不正なレスポンスです"])
      }

      // syncToken期限切れは 410 GONE（公式）
      if http.statusCode == 410 {
        throw CalendarSyncError.syncTokenExpired
      }

      guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw NSError(
          domain: "GoogleCalendarClient", code: http.statusCode,
          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
      }

      let decoded = try JSONDecoder().decode(EventsListResponse.self, from: data)

      all.append(contentsOf: decoded.items.compactMap { $0.toDomain() })
      pageToken = decoded.nextPageToken
      if let t = decoded.nextSyncToken { newestSyncToken = t }

    } while pageToken != nil

    return ListResult(events: all, nextSyncToken: newestSyncToken)
  }
}

enum CalendarSyncError: Error {
  case syncTokenExpired
}

private struct EventsListResponse: Decodable {
  let items: [EventItem]
  let nextSyncToken: String?
  let nextPageToken: String?
}

private struct EventItem: Decodable {
  let id: String
  let summary: String?
  let description: String?
  let start: EventDateTime
  let end: EventDateTime?
  let status: String?
  let updated: String?

  func toDomain() -> GoogleCalendarEvent? {
    let title = summary ?? "（予定）"
    let status = status ?? "confirmed"
    let updatedDate = updated.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

    if let d = start.date {
      guard let startDate = ISO8601DateFormatter.dateOnly.date(from: d) else { return nil }
      let endDate: Date? = end?.date.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
      return GoogleCalendarEvent(
        id: id, title: title, start: startDate, end: endDate, isAllDay: true,
        description: description, status: status, updated: updatedDate)
    } else if let dt = start.dateTime {
      guard let startDate = ISO8601DateFormatter().date(from: dt) else { return nil }
      let endDate = end?.dateTime.flatMap { ISO8601DateFormatter().date(from: $0) }
      return GoogleCalendarEvent(
        id: id, title: title, start: startDate, end: endDate, isAllDay: false,
        description: description, status: status, updated: updatedDate)
    } else {
      return nil
    }
  }
}

private struct EventDateTime: Decodable {
  let dateTime: String?
  let date: String?
}

// Date-only をパースするための小技
extension ISO8601DateFormatter {
  fileprivate static var dateOnly: DateFormatter {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f
  }
}
