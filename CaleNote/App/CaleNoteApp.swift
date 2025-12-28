import SwiftUI
import SwiftData

@main
struct CaleNoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            ScheduleEntry.self
        ])
    }
}
