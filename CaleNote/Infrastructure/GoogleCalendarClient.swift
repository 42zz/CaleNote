import Foundation

struct GoogleCalendarEvent: Identifiable {
  let id: String
  let title: String
  let start: Date
  let end: Date?
  let isAllDay: Bool
  let description: String?
}

enum GoogleCalendarClient {
  static func listEvents(
    accessToken: String,
    timeMin: Date,
    timeMax: Date
  ) async throws -> [GoogleCalendarEvent] {

    var components = URLComponents(
      string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
    let iso = ISO8601DateFormatter()

    components.queryItems = [
      URLQueryItem(name: "timeMin", value: iso.string(from: timeMin)),
      URLQueryItem(name: "timeMax", value: iso.string(from: timeMax)),
      URLQueryItem(name: "singleEvents", value: "true"),
      URLQueryItem(name: "orderBy", value: "startTime"),
      URLQueryItem(name: "maxResults", value: "2500"),
      // まずは必要最低限。慣れたらさらに絞る
      URLQueryItem(
        name: "fields",
        value: "items(id,summary,description,start(dateTime,date),end(dateTime,date))"),
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(
        domain: "GoogleCalendarClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "不正なレスポンスです"]
      )
    }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "GoogleCalendarClient", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
    }

    let decoded = try JSONDecoder().decode(EventsListResponse.self, from: data)
    return decoded.items.compactMap { $0.toDomain() }
  }
}

private struct EventsListResponse: Decodable {
  let items: [EventItem]
}

private struct EventItem: Decodable {
  let id: String
  let summary: String?
  let description: String?
  let start: EventDateTime
  let end: EventDateTime?

  func toDomain() -> GoogleCalendarEvent? {
    let title = summary ?? "（予定）"
    // 終日: start.date があり dateTime が無い
    if let d = start.date {
      // 終日イベントはDateだけで来るので、ローカル00:00として扱う
      // 表示は後で調整可能
      guard let startDate = ISO8601DateFormatter.dateOnly.date(from: d) else { return nil }
      let endDate: Date? = end?.date.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
      return GoogleCalendarEvent(
        id: id, title: title, start: startDate, end: endDate, isAllDay: true,
        description: description)
    } else if let dt = start.dateTime {
      guard let startDate = ISO8601DateFormatter().date(from: dt) else { return nil }
      let endDate = end?.dateTime.flatMap { ISO8601DateFormatter().date(from: $0) }
      return GoogleCalendarEvent(
        id: id, title: title, start: startDate, end: endDate, isAllDay: false,
        description: description)
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
