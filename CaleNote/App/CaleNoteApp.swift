import SwiftUI
import SwiftData

@main
struct CaleNoteApp: App {
    @StateObject private var authService = GoogleAuthService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
        .modelContainer(for: [
            ScheduleEntry.self
        ])
    }
}
