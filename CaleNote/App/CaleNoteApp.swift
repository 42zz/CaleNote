import SwiftUI
import SwiftData

@main
struct CaleNoteApp: App {
    // 認証サービス
    @StateObject private var authService = GoogleAuthService.shared

    // 検索インデックスサービス
    @StateObject private var searchIndexService: SearchIndexService

    // 関連エントリーインデックスサービス
    @StateObject private var relatedIndexService: RelatedEntriesIndexService

    // カレンダーリストサービス
    @StateObject private var calendarListService: CalendarListService

    // モデルコンテナの保持
    let container: ModelContainer

    // 同期サービス
    @StateObject private var syncService: CalendarSyncService

    init() {
        do {
            // スキーマ定義（CalendarInfoを追加）
            let schema = Schema([
                ScheduleEntry.self,
                CalendarInfo.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])

            // サービスの初期化
            let context = container.mainContext
            let apiClient = GoogleCalendarClient()

            let searchIndex = SearchIndexService()
            searchIndex.rebuildIndex(modelContext: context)

            let relatedIndex = RelatedEntriesIndexService()
            relatedIndex.rebuildIndex(modelContext: context)

            let calendarList = CalendarListService(
                apiClient: apiClient,
                modelContext: context
            )

            let sync = CalendarSyncService(
                apiClient: apiClient,
                authService: .shared,
                searchIndexService: searchIndex,
                relatedIndexService: relatedIndex,
                errorHandler: .shared,
                modelContext: context,
                calendarSettings: .shared,
                rateLimiter: .shared
            )

            _syncService = StateObject(wrappedValue: sync)
            _searchIndexService = StateObject(wrappedValue: searchIndex)
            _relatedIndexService = StateObject(wrappedValue: relatedIndex)
            _calendarListService = StateObject(wrappedValue: calendarList)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(syncService)
                .environmentObject(searchIndexService)
                .environmentObject(relatedIndexService)
                .environmentObject(calendarListService)
        }
        .modelContainer(container)
    }
}
