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
  let privateProps: [String: String]?
}

struct GoogleCalendarListItem: Identifiable {
  let id: String  // calendarId
  let summary: String
  let primary: Bool
  let colorId: String?
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
      let encodedId = encodedCalendarId(calendarId)
      var components = URLComponents(
        string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events")!
      let iso = ISO8601DateFormatter()

      var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "singleEvents", value: "true"),
        URLQueryItem(name: "showDeleted", value: "true"),
        URLQueryItem(name: "maxResults", value: "2500"),
        URLQueryItem(
          name: "fields",
          value:
            "items(id,summary,description,start(dateTime,date),end(dateTime,date),status,updated,extendedProperties(private,shared)),nextSyncToken,nextPageToken"
        ),
      ]

      // syncToken があるなら増分同期、無ければ期間指定
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

private func encodedCalendarId(_ calendarId: String) -> String {
  // calendarId は URL の「パス」に入るので urlPathAllowed を使う
  // ただし "/" はパス区切りになるので除外しておく（念のため）
  var allowed = CharacterSet.urlPathAllowed
  allowed.remove(charactersIn: "/")
  return calendarId.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarId
}

enum CalendarSyncError: Error {
  case syncTokenExpired
}

private struct EventsListResponse: Decodable {
  let items: [EventItem]
  let nextSyncToken: String?
  let nextPageToken: String?
}

private struct EventWriteRequest: Encodable {
  struct EventDateTime: Encodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
  }

  struct ExtendedProperties: Encodable {
    let `private`: [String: String]?
    let shared: [String: String]?
  }

  let summary: String?
  let description: String?
  let start: EventDateTime
  let end: EventDateTime
  let extendedProperties: ExtendedProperties?

  init(
    summary: String?,
    description: String?,
    start: EventDateTime,
    end: EventDateTime,
    extendedProperties: ExtendedProperties? = nil
  ) {
    self.summary = summary
    self.description = description
    self.start = start
    self.end = end
    self.extendedProperties = extendedProperties
  }
}

private struct EventItem: Decodable {
  let id: String
  let summary: String?
  let description: String?
  let start: EventDateTime
  let end: EventDateTime?
  let status: String?
  let updated: String?
  let extendedProperties: ExtendedProperties?

  struct ExtendedProperties: Decodable {
    let `private`: [String: String]?
    let shared: [String: String]?
  }

  func toDomain() -> GoogleCalendarEvent? {
    let title = summary ?? "（予定）"
    let status = status ?? "confirmed"
    let updatedDate = updated.flatMap { GoogleRFC3339.parse($0) } ?? Date()

    if let d = start.date {
      guard let startDate = ISO8601DateFormatter.dateOnly.date(from: d) else { return nil }
      let endDate: Date? = end?.date.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }

      return GoogleCalendarEvent(
        id: id,
        title: title,
        start: startDate,
        end: endDate,
        isAllDay: true,
        description: description,
        status: status,
        updated: updatedDate,
        privateProps: extendedProperties?.private
      )
    }

    if let dt = start.dateTime {
      guard let startDate = GoogleRFC3339.parse(dt) else { return nil }
      let endDate = end?.dateTime.flatMap { GoogleRFC3339.parse($0) }

      return GoogleCalendarEvent(
        id: id,
        title: title,
        start: startDate,
        end: endDate,
        isAllDay: false,
        description: description,
        status: status,
        updated: updatedDate,
        privateProps: extendedProperties?.private
      )
    }

    return nil
  }
}

private struct EventDateTime: Decodable {
  let dateTime: String?
  let date: String?
}

private enum DateFormatters {
  static let isoDateTime: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  static let dateOnly: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()
}

private struct CalendarListResponse: Decodable {
  let items: [CalendarListItem]
}

private struct CalendarListItem: Decodable {
  let id: String
  let summary: String?
  let primary: Bool?
  let colorId: String?
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

private enum GoogleRFC3339 {
  static let withFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  static let withoutFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  static func parse(_ s: String) -> Date? {
    if let d = withFractional.date(from: s) { return d }
    if let d = withoutFractional.date(from: s) { return d }
    return nil
  }
}

extension GoogleCalendarClient {
  static func insertEvent(
    accessToken: String,
    calendarId: String,
    title: String,
    description: String,
    start: Date,
    end: Date,
    appPrivateProperties: [String: String]
  ) async throws -> GoogleCalendarEvent {

    let reqBody = EventWriteRequest(
      summary: title,
      description: description,
      start: EventWriteRequest.EventDateTime(
        dateTime: DateFormatters.isoDateTime.string(from: start),
        date: nil,
        timeZone: TimeZone.current.identifier
      ),
      end: EventWriteRequest.EventDateTime(
        dateTime: DateFormatters.isoDateTime.string(from: end),
        date: nil,
        timeZone: TimeZone.current.identifier
      ),
      extendedProperties: EventWriteRequest.ExtendedProperties(
        private: appPrivateProperties,
        shared: nil
      )
    )

    let encodedId = encodedCalendarId(calendarId)
    var components = URLComponents(
      string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events")!
    components.queryItems = [
      URLQueryItem(
        name: "fields",
        value:
          "id,summary,description,start(dateTime,date),end(dateTime,date),status,updated,extendedProperties(private)"
      )
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(reqBody)

    let (data, response) = try await URLSession.shared.data(for: request)
    try ensure2xx(response: response, data: data)

    let decoded = try JSONDecoder().decode(EventItem.self, from: data)
    guard let event = decoded.toDomain() else {
      throw NSError(
        domain: "GoogleCalendarClient", code: 2001,
        userInfo: [NSLocalizedDescriptionKey: "insertのレスポンスが解釈できません"])
    }
    return event
  }

  static func updateEvent(
    accessToken: String,
    calendarId: String,
    eventId: String,
    title: String,
    description: String,
    start: Date,
    end: Date,
    appPrivateProperties: [String: String]
  ) async throws -> GoogleCalendarEvent {

    let reqBody = EventWriteRequest(
      summary: title,
      description: description,
      start: EventWriteRequest.EventDateTime(
        dateTime: DateFormatters.isoDateTime.string(from: start),
        date: nil,
        timeZone: TimeZone.current.identifier
      ),
      end: EventWriteRequest.EventDateTime(
        dateTime: DateFormatters.isoDateTime.string(from: end),
        date: nil,
        timeZone: TimeZone.current.identifier
      ),
      extendedProperties: EventWriteRequest.ExtendedProperties(
        private: appPrivateProperties,
        shared: nil
      )
    )

    let encodedId = encodedCalendarId(calendarId)
    var components = URLComponents(
      string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events/\(eventId)")!
    components.queryItems = [
      URLQueryItem(
        name: "fields",
        value:
          "id,summary,description,start(dateTime,date),end(dateTime,date),status,updated,extendedProperties(private)"
      )
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "PUT"  // updateは全量更新 :contentReference[oaicite:1]{index=1}
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(reqBody)

    let (data, response) = try await URLSession.shared.data(for: request)
    try ensure2xx(response: response, data: data)

    let decoded = try JSONDecoder().decode(EventItem.self, from: data)
    guard let event = decoded.toDomain() else {
      throw NSError(
        domain: "GoogleCalendarClient", code: 2002,
        userInfo: [NSLocalizedDescriptionKey: "updateのレスポンスが解釈できません"])
    }
    return event
  }

  private static func ensure2xx(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw NSError(
        domain: "GoogleCalendarClient", code: 9998,
        userInfo: [NSLocalizedDescriptionKey: "不正なレスポンスです"])
    }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "GoogleCalendarClient", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
    }
  }
  static func listCalendars(accessToken: String) async throws -> [GoogleCalendarListItem] {
    var components = URLComponents(
      string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
    components.queryItems = [
      URLQueryItem(name: "maxResults", value: "250"),
      URLQueryItem(name: "fields", value: "items(id,summary,primary,colorId)"),
    ]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(
        domain: "GoogleCalendarClient", code: 20,
        userInfo: [NSLocalizedDescriptionKey: "不正なレスポンスです"])
    }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "GoogleCalendarClient", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
    }

    let decoded = try JSONDecoder().decode(CalendarListResponse.self, from: data)
    return decoded.items.map {
      GoogleCalendarListItem(
        id: $0.id,
        summary: $0.summary ?? "（無題）",
        primary: $0.primary ?? false,
        colorId: $0.colorId
      )
    }
  }
  static func deleteEvent(
    accessToken: String,
    calendarId: String,
    eventId: String
  ) async throws {
    let encodedId = encodedCalendarId(calendarId)
    let url = URL(
      string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events/\(eventId)")!

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(
        domain: "GoogleCalendarClient", code: 3001,
        userInfo: [NSLocalizedDescriptionKey: "不正なレスポンスです"])
    }

    // 204 No Content が典型。404でも「すでに無い」なら成功扱いにして良い
    if http.statusCode == 404 { return }
    guard (200..<300).contains(http.statusCode) else {
      throw NSError(
        domain: "GoogleCalendarClient", code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
    }
  }
}
