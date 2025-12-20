import Combine
import Foundation

@MainActor
final class CalendarEventStore: ObservableObject {
  @Published private(set) var events: [GoogleCalendarEvent] = []
  @Published private(set) var lastErrorMessage: String?

  func load(auth: GoogleAuthService, timeMin: Date, timeMax: Date) async {
    do {
      try await auth.ensureCalendarScopeGranted()
      let token = try await auth.validAccessToken()
      let list = try await GoogleCalendarClient.listEvents(
        accessToken: token, timeMin: timeMin, timeMax: timeMax)
      self.events = list
      self.lastErrorMessage = nil
    } catch {
      self.lastErrorMessage = error.localizedDescription
    }
  }
}
