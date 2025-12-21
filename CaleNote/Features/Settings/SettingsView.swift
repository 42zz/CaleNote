import GoogleSignIn
import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @Environment(\.modelContext) private var modelContext

    // Boolでソートすると死ぬので、ここは文字列ソートで安定させる
    @Query(sort: \CachedCalendar.summary, order: .forward)
    private var calendars: [CachedCalendar]

    @State private var errorMessage: String?
    private let listSync = CalendarListSyncService()

    private var calendarsPrimaryFirst: [CachedCalendar] {
        calendars.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
            return a.summary < b.summary
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Google連携") {
                    if let user = auth.user {
                        Text("ログイン中: \(user.profile?.email ?? "不明")")
                        Button("ログアウト") { auth.signOut() }
                    } else {
                        Text("未ログイン")
                    }
                }

                Section("表示するカレンダー") {
                    if calendarsPrimaryFirst.isEmpty {
                        Text("カレンダー一覧がありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendarsPrimaryFirst) { cal in
                            Toggle(
                                isOn: Binding(
                                    get: { cal.isEnabled },
                                    set: { newValue in
                                        cal.isEnabled = newValue
                                        cal.updatedAt = Date()
                                        try? modelContext.save()
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cal.summary)
                                    if cal.isPrimary {
                                        Text("メイン")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("カレンダーの色") {
                    if calendarsPrimaryFirst.isEmpty {
                        Text("まず一覧を同期してください。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendarsPrimaryFirst) { cal in
                            NavigationLink {
                                CalendarColorPickerView(calendar: cal)
                            } label: {
                                HStack {
                                    Text(cal.summary)
                                    Spacer()
                                    Text(cal.userColorHex)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                Button("同期") {
                    Task { await syncCalendarList() }
                }
            }
            .task {
                await syncCalendarList()
            }
        }
    }

    private func syncCalendarList() async {
        do {
            try await listSync.syncCalendarList(auth: auth, modelContext: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
