import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var auth = GoogleAuthService()
    @Environment(\.modelContext) private var modelContext

    @Query private var cachedCalendars: [CachedCalendar]

    @State private var needsOnboarding = true
    @State private var isCheckingOnboarding = true

    var body: some View {
        Group {
            if isCheckingOnboarding {
                // 初期チェック中
                ProgressView()
            } else if needsOnboarding {
                // オンボーディング表示
                OnboardingCoordinatorView {
                    // オンボーディング完了
                    checkOnboardingStatus()
                }
                .environmentObject(auth)
            } else {
                // 通常のTabView
                TabView {
                    TimelineView()
                        .tabItem { Label("メイン", systemImage: "list.bullet") }
                        .environmentObject(auth)

                    SettingsView()
                        .tabItem { Label("設定", systemImage: "gearshape") }
                        .environmentObject(auth)
                }
            }
        }
        .task {
            await auth.restorePreviousSignInIfPossible()
            checkOnboardingStatus()
        }
        .onChange(of: auth.user) { _, _ in
            // ログアウト時などに再チェック
            checkOnboardingStatus()
        }
    }

    private func checkOnboardingStatus() {
        // 判定条件:
        // 1. 認証トークンが有効（auth.user が存在する）
        // 2. CachedCalendarが存在する
        // 3. 少なくとも1件 isEnabled のカレンダーがある

        let hasUser = auth.user != nil
        let hasCalendars = !cachedCalendars.isEmpty
        let hasEnabledCalendar = cachedCalendars.contains { $0.isEnabled }

        needsOnboarding = !(hasUser && hasCalendars && hasEnabledCalendar)
        isCheckingOnboarding = false
    }
}
