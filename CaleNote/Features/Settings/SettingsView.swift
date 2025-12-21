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
    @State private var writeCalendarId: String? = JournalWriteSettings.loadWriteCalendarId()

    @Query(
        filter: #Predicate<JournalEntry> { $0.needsCalendarSync == true },
        sort: \JournalEntry.updatedAt, order: .reverse)
    private var pendingEntries: [JournalEntry]

    private let journalSync = JournalCalendarSyncService()

    private var calendarsPrimaryFirst: [CachedCalendar] {
        calendars.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
            return a.summary < b.summary
        }
    }

    private func defaultWriteCalendarId(from enabled: [CachedCalendar]) -> String {
        if let saved = writeCalendarId, enabled.contains(where: { $0.calendarId == saved }) {
            return saved
        }
        if let primary = enabled.first(where: { $0.isPrimary }) {
            return primary.calendarId
        }
        return enabled.first!.calendarId
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

                Section("ジャーナルの書き込み先") {
                    let enabledCalendars = calendars.filter { $0.isEnabled }

                    if enabledCalendars.isEmpty {
                        Text("先に表示するカレンダーを1つ以上ONにしてください。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "書き込み先",
                            selection: Binding(
                                get: {
                                    writeCalendarId
                                        ?? defaultWriteCalendarId(from: enabledCalendars)
                                },
                                set: { newValue in
                                    writeCalendarId = newValue
                                    JournalWriteSettings.saveWriteCalendarId(newValue)
                                }
                            )
                        ) {
                            ForEach(enabledCalendars) { cal in
                                Text(cal.summary).tag(cal.calendarId)
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

                Section("同期待ち") {
                    if pendingEntries.isEmpty {
                        Text("同期待ちはありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(pendingEntries.count)件の同期待ちがあります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("まとめて再送") {
                            Task { await resendAll() }
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
        }
    }

    private func resendAll() async {
        do {
            let targetCalendarId = JournalWriteSettings.loadWriteCalendarId() ?? "primary"

            for entry in pendingEntries {
                try await journalSync.syncOne(
                    entry: entry,
                    targetCalendarId: entry.linkedCalendarId ?? targetCalendarId,
                    auth: auth,
                    modelContext: modelContext
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
