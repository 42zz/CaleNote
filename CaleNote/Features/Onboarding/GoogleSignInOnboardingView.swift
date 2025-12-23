import SwiftUI
import SwiftData

struct GoogleSignInOnboardingView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @Environment(\.modelContext) private var modelContext

    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var isSyncingCalendars = false

    let onComplete: () -> Void

    private let listSync = CalendarListSyncService()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // ロゴ・タイトルエリア
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("CaleNote へようこそ")
                    .font(.largeTitle)
                    .bold()

                Text("Google Calendar と同期して\nジャーナルを記録しましょう")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Google Sign-In ボタン
            VStack(spacing: 16) {
                if isSigningIn || isSyncingCalendars {
                    ProgressView()
                        .scaleEffect(1.5)
                    if isSyncingCalendars {
                        Text("カレンダーを取得中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        signIn()
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Google でサインイン")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func signIn() {
        Task {
            isSigningIn = true
            errorMessage = nil

            do {
                // Google Sign-In
                try await auth.signIn()

                // カレンダー一覧の初回同期
                isSyncingCalendars = true
                isSigningIn = false

                try await listSync.syncCalendarList(
                    auth: auth,
                    modelContext: modelContext
                )

                // 成功したら次ステップへ
                onComplete()

            } catch {
                isSigningIn = false
                isSyncingCalendars = false
                errorMessage = "サインインに失敗しました: \(error.localizedDescription)"
            }
        }
    }
}
