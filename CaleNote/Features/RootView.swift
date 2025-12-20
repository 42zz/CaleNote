import SwiftUI

struct RootView: View {
    @StateObject private var auth = GoogleAuthService()

    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("メイン", systemImage: "list.bullet") }
                .environmentObject(auth)

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .environmentObject(auth)
        }
        .task {
            await auth.restorePreviousSignInIfPossible()
        }
    }
}
