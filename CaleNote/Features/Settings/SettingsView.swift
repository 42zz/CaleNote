import GoogleSignIn
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Google連携") {
                    if let user = auth.user {
                        Text("ログイン中: \(user.profile?.email ?? "不明")")

                        Button("ログアウト") {
                            auth.signOut()
                        }
                    } else {
                        Button("Googleでログイン") {
                            Task {
                                do {
                                    try await auth.signIn()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}
