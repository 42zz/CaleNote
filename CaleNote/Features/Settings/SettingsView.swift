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
    
    @State private var isImportingArchive = false
    @State private var archiveProgressText: String?
    private let archiveSync = ArchiveSyncService()

    @Query(
        filter: #Predicate<JournalEntry> { $0.needsCalendarSync == true },
        sort: \JournalEntry.updatedAt, order: .reverse)
    private var pendingEntries: [JournalEntry]

    private let journalSync = JournalCalendarSyncService()
    @State private var pastDays: Int = SyncSettings.pastDays()
    @State private var futureDays: Int = SyncSettings.futureDays()

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
                        Button("Googleでログイン") {
                            Task {
                                do {
                                    try await auth.signIn()
                                    errorMessage = nil
                                    // ログイン成功後、自動的にカレンダー一覧を同期
                                    await syncCalendarList()
                                } catch {
                                    errorMessage = "ログイン失敗: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }

                Section("表示するカレンダー") {
                    if calendarsPrimaryFirst.isEmpty {
                        Text("カレンダー一覧がありません。")
                            .foregroundStyle(.secondary)
                        if auth.user != nil {
                            Button("カレンダー一覧を同期") {
                                Task { await syncCalendarList() }
                            }
                        }
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
                        Button("カレンダー一覧を再同期") {
                            Task { await syncCalendarList() }
                        }
                        .font(.caption)
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

                Section("同期対象期間") {
                    Stepper("過去 \(pastDays) 日", value: $pastDays, in: 1...365, step: 1)
                        .onChange(of: pastDays) { _, newValue in
                            SyncSettings.save(pastDays: newValue, futureDays: futureDays)
                        }

                    Stepper("未来 \(futureDays) 日", value: $futureDays, in: 1...365, step: 1)
                        .onChange(of: futureDays) { _, newValue in
                            SyncSettings.save(pastDays: pastDays, futureDays: newValue)
                        }

                    Text("デフォルトは過去30日〜未来30日です。範囲を広げるほど同期とキャッシュが重くなります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                
                Section("長期キャッシュ") {
                    Button {
                        Task { await importArchive() }
                    } label: {
                        Text(isImportingArchive ? "取り込み中…" : "長期キャッシュを取り込む（全期間）")
                    }
                    .disabled(isImportingArchive)

                    if let archiveProgressText {
                        Text(archiveProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("過去の振り返り用にカレンダーイベントを端末に保存します。件数が多いと時間がかかります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    
    @MainActor
    private func syncCalendarList() async {
        guard auth.user != nil else {
            errorMessage = "ログインしてください"
            return
        }
        
        do {
            try await listSync.syncCalendarList(
                auth: auth,
                modelContext: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "カレンダー一覧の同期失敗: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func importArchive() async {
        if isImportingArchive { return }
        isImportingArchive = true
        defer { isImportingArchive = false }

        do {
            // 対象は「表示ONのカレンダーだけ」でもいいし、「全カレンダー」でもいい
            // まずは isEnabled のみで十分
            let targets = calendars.filter { $0.isEnabled }
            if targets.isEmpty {
                archiveProgressText = "取り込み対象のカレンダーがありません（表示カレンダーをONにしてください）"
                return
            }

            try await archiveSync.importAllEventsToArchive(
                auth: auth,
                modelContext: modelContext,
                calendars: targets
            ) { p in
                Task { @MainActor in
                    archiveProgressText =
                        "カレンダー: \(p.calendarId)\n" +
                        "進捗: \(p.fetchedRanges)/\(p.totalRanges)\n" +
                        "反映: \(p.upserted) / 削除: \(p.deleted)"
                }
            }

            archiveProgressText = "長期キャッシュ取り込み完了"
        } catch {
            archiveProgressText = "取り込み失敗: \(error.localizedDescription)"
        }
    }

}
