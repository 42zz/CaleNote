import SwiftUI
import SwiftData

@main
struct CaleNoteApp: App {
    // 認証サービス
    @StateObject private var authService = GoogleAuthService.shared
    
    // モデルコンテナの保持
    let container: ModelContainer
    
    // 同期サービス
    @StateObject private var syncService: CalendarSyncService

    init() {
        do {
            // スキーマ定義
            let schema = Schema([
                ScheduleEntry.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
            
            // サービスの初期化
            let context = container.mainContext
            let sync = CalendarSyncService(
                apiClient: GoogleCalendarClient(),
                authService: .shared,
                errorHandler: .shared,
                modelContext: context,
                calendarSettings: .shared,
                rateLimiter: .shared
            )
            _syncService = StateObject(wrappedValue: sync)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(syncService)
        }
        .modelContainer(container)
    }
}