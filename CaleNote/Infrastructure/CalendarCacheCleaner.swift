import Foundation
import SwiftData

@MainActor
final class CalendarCacheCleaner {
  func cleanupEventsOutsideWindow(
    modelContext: ModelContext,
    timeMin: Date,
    timeMax: Date
  ) throws -> Int {
    let p = #Predicate<CachedCalendarEvent> { ev in
      ev.start < timeMin || ev.start > timeMax
    }
    let d = FetchDescriptor(predicate: p)
    let targets = try modelContext.fetch(d)

    for ev in targets {
      modelContext.delete(ev)
    }
    try modelContext.save()
    return targets.count
  }
}
