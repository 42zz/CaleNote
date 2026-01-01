import SwiftData
import SwiftUI

@main
struct CaleNoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
            AppEnvironment.applyOverrides()

            // スキーマ定義（CalendarInfoを追加）
            let schema = Schema([
                ScheduleEntry.self,
                CalendarInfo.self
            ])
            let config: ModelConfiguration
            if AppEnvironment.isUITesting {
                config = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                let storeURL = try DataProtection.protectedStoreURL(filename: "CaleNote.sqlite")
                config = ModelConfiguration(url: storeURL)
                DataProtection.applyFileProtection(to: storeURL)
            }
            container = try ModelContainer(for: schema, configurations: [config])

            // サービスの初期化
            let context = container.mainContext
            let apiClient = GoogleCalendarClient()

            let searchIndex = SearchIndexService()
            let relatedIndex = RelatedEntriesIndexService()

            if AppEnvironment.isUITesting && AppEnvironment.shouldSeedData {
                UITestDataSeeder.seed(modelContext: context)
            }

            searchIndex.rebuildIndex(modelContext: context)
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

            BackgroundTaskManager.shared.configure(
                syncService: sync,
                calendarListService: calendarList,
                searchIndexService: searchIndex,
                relatedIndexService: relatedIndex,
                modelContext: context
            )
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
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .background:
                BackgroundTaskManager.shared.scheduleAppRefresh(reason: "scenePhase.background")
                BackgroundTaskManager.shared.scheduleProcessing(reason: "scenePhase.background")
            case .active:
                BackgroundTaskManager.shared.scheduleAppRefresh(reason: "scenePhase.active")
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
