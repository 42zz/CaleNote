import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var auth = GoogleAuthService()
    @Environment(\.modelContext) private var modelContext

    @Query private var cachedCalendars: [CachedCalendar]

    @State private var needsOnboarding = true
    @State private var isCheckingOnboarding = true
    @State private var selectedTab: Int = 0
    @State private var mainTabTapTrigger: Int = 0

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
                // カスタムタブバーを使用して同じタブの再タップを検知
                ZStack(alignment: .bottom) {
                    // タブコンテンツ（両方とも常に保持してopacityで切り替え）
                    TimelineView(
                        selectedTab: $selectedTab,
                        tabTapTrigger: $mainTabTapTrigger
                    )
                    .environmentObject(auth)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .zIndex(selectedTab == 0 ? 1 : 0)

                    SettingsView()
                        .environmentObject(auth)
                        .opacity(selectedTab == 1 ? 1 : 0)
                        .zIndex(selectedTab == 1 ? 1 : 0)

                    // カスタムタブバー
                    HStack(spacing: 0) {
                        Button {
                            if selectedTab == 0 {
                                // 同じタブを再度タップした場合
                                mainTabTapTrigger += 1
                                print("🔔 メインタブが再度タップされました（トリガー: \(mainTabTapTrigger)）")
                            } else {
                                selectedTab = 0
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 24))
                                Text("メイン")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedTab == 0 ? .blue : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        Button {
                            selectedTab = 1
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 24))
                                Text("設定")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedTab == 1 ? .blue : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(Color(UIColor.systemBackground).opacity(0.95))
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(Color.gray.opacity(0.3)),
                        alignment: .top
                    )
                    .zIndex(100)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
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
