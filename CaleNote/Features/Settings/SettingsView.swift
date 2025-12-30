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
    @State private var archiveTask: Task<Void, Never>?
    private let archiveSync = ArchiveSyncService()

    // データ復旧用
    @State private var isRecovering = false
    @State private var recoveryProgressText: String?
    @State private var recoveryTask: Task<Void, Never>?
    @State private var showRecoveryConfirmation = false
    private let recoveryService = DataRecoveryService()

    @Query(
        filter: #Predicate<JournalEntry> { $0.needsCalendarSync == true },
        sort: \JournalEntry.updatedAt, order: .reverse)
    private var pendingEntries: [JournalEntry]

    private let journalSync = JournalCalendarSyncService()
    @State private var pastDays: Int = SyncSettings.pastDays()
    @State private var futureDays: Int = SyncSettings.futureDays()
    @State private var eventDurationMinutes: Int = JournalWriteSettings.eventDurationMinutes()

    @State private var developerTapCount: Int = 0
    @State private var isDeveloperModeEnabled: Bool = UserDefaults.standard.bool(
        forKey: "isDeveloperModeEnabled")

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
                            NavigationLink {
                                CalendarSettingsView(calendar: cal)
                            } label: {
                                HStack {
                                    // カラーチップとアイコン
                                    ZStack {
                                        Circle()
                                            .fill(
                                                Color(hex: cal.userColorHex)?.opacity(0.2)
                                                    ?? .blue.opacity(0.2)
                                            )
                                            .frame(width: 32, height: 32)

                                        Image(systemName: cal.iconName)
                                            .font(.caption)
                                            .foregroundStyle(Color(hex: cal.userColorHex) ?? .blue)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cal.summary)
                                        if cal.isPrimary {
                                            Text("メイン")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    // 表示状態をインジケーターで表示
                                    if cal.isEnabled {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
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

                Section("エントリー設定") {
                    // デフォルトの書き込み先カレンダー選択
                    let enabledCalendars = calendarsPrimaryFirst.filter { $0.isEnabled }
                    if enabledCalendars.isEmpty {
                        Text("表示するカレンダーがありません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("デフォルトの書き込み先", selection: Binding(
                            get: {
                                writeCalendarId ?? defaultWriteCalendarId(from: enabledCalendars)
                            },
                            set: { selectedCalendarId in
                                writeCalendarId = selectedCalendarId
                                JournalWriteSettings.saveWriteCalendarId(selectedCalendarId)
                            }
                        )) {
                            ForEach(enabledCalendars) { cal in
                                HStack {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                Color(hex: cal.userColorHex)?.opacity(0.2)
                                                    ?? .blue.opacity(0.2)
                                            )
                                            .frame(width: 24, height: 24)
                                        Image(systemName: cal.iconName)
                                            .font(.caption2)
                                            .foregroundStyle(Color(hex: cal.userColorHex) ?? .blue)
                                    }
                                    Text(cal.summary)
                                    if cal.isPrimary {
                                        Text("メイン")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(cal.calendarId)
                            }
                        }
                    }

                    Stepper(
                        value: $eventDurationMinutes,
                        in: 1...480,
                        step: 5
                    ) {
                        HStack {
                            Text("エントリーの時間")
                            Spacer()
                            Text("\(eventDurationMinutes)分")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: eventDurationMinutes) { oldValue, newValue in
                        JournalWriteSettings.saveEventDurationMinutes(newValue)
                    }

                    Text("新規作成時にカレンダーに登録するエントリーの時間を設定します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("関連する過去のエントリー表示設定") {
                    RelatedMemorySettingsSection()
                }

                Section("長期キャッシュ（一括取り込み）") {
                    if !isImportingArchive {
                        Button {
                            archiveTask = Task { await importArchive() }
                        } label: {
                            Text("表示中の全カレンダーを取り込む")
                        }
                    } else {
                        HStack {
                            Button("取り込み中…") {}
                                .disabled(true)
                            Spacer()
                            Button("キャンセル") {
                                cancelArchiveImport()
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    if let archiveProgressText {
                        Text(archiveProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("表示中の全カレンダーの長期キャッシュを一括で取り込みます。各カレンダーごとの取り込みは、カレンダー設定画面から行えます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("同期待ち") {
                    if pendingEntries.isEmpty {
                        Text("同期待ちのジャーナルはありません")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(pendingEntries.count)件の同期待ちがあります")
                            .foregroundStyle(.orange)

                        Button {
                            Task { await resendAll() }
                        } label: {
                            Text("まとめて再送")
                        }

                        ForEach(pendingEntries.prefix(5)) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title ?? "無題")
                                        .font(.subheadline)
                                    Text(entry.eventDate, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }

                        if pendingEntries.count > 5 {
                            Text("他\(pendingEntries.count - 5)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("データ復旧") {
                    if !isRecovering {
                        Button {
                            showRecoveryConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle")
                                Text("Google Calendarから再構築")
                            }
                        }
                        .foregroundStyle(.orange)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("復旧中…")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("キャンセル") {
                                cancelRecovery()
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    if let recoveryProgressText {
                        Text(recoveryProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("ローカルデータに問題がある場合、Google Calendarから全データを再取得して復旧します。ジャーナルは保持され、カレンダーとの紐付けが再構築されます。")
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

                // 開発者向けツール（隠し導線）
                if isDeveloperModeEnabled {
                    Section("開発者向け") {
                        NavigationLink {
                            DeveloperToolsView()
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                Text("開発者向けツール")
                            }
                        }
                    }
                }

                // バージョン情報（7回タップで開発者モード有効化）
                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                                ?? "0.21"
                        )
                        .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        developerTapCount += 1
                        if developerTapCount >= 7 {
                            isDeveloperModeEnabled.toggle()
                            UserDefaults.standard.set(
                                isDeveloperModeEnabled, forKey: "isDeveloperModeEnabled")
                            developerTapCount = 0
                        }
                        // 5秒後にカウントリセット
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            developerTapCount = 0
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // タブバーの高さ分のスペースを確保
                Color.clear.frame(height: 60)
            }
            .navigationTitle("設定")
            .confirmationDialog(
                "データを再構築しますか？",
                isPresented: $showRecoveryConfirmation,
                titleVisibility: .visible
            ) {
                Button("再構築を開始", role: .destructive) {
                    recoveryTask = Task { await performRecovery() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ローカルのキャッシュデータを削除し、Google Calendarから全データを再取得します。ジャーナルは保持されますが、処理には時間がかかります。")
            }
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
        defer {
            isImportingArchive = false
            archiveTask = nil
        }

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
                        "カレンダー: \(p.calendarId)\n" + "進捗: \(p.fetchedRanges)/\(p.totalRanges)\n"
                        + "反映: \(p.upserted) / 削除: \(p.deleted)"
                }
            }

            archiveProgressText = "長期キャッシュ取り込み完了"
        } catch is CancellationError {
            archiveProgressText = "取り込みをキャンセルしました（進捗は保存されています）"
        } catch {
            archiveProgressText = "取り込み失敗: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func cancelArchiveImport() {
        archiveTask?.cancel()
        archiveTask = nil
    }

    @MainActor
    private func performRecovery() async {
        guard auth.user != nil else {
            recoveryProgressText = "Googleにログインしてください"
            return
        }

        if isRecovering { return }
        isRecovering = true
        defer {
            isRecovering = false
            recoveryTask = nil
        }

        do {
            try await recoveryService.performFullRecovery(
                auth: auth,
                modelContext: modelContext,
                preserveJournals: true
            ) { progress in
                Task { @MainActor in
                    switch progress.phase {
                    case .idle:
                        recoveryProgressText = nil
                    case .deletingLocalData:
                        recoveryProgressText = "ローカルデータを削除中..."
                    case .syncingCalendarList:
                        recoveryProgressText = "カレンダー一覧を同期中..."
                    case .fetchingEvents:
                        if progress.totalRanges > 0 {
                            recoveryProgressText = "イベント取得中...\n" +
                                "カレンダー: \(progress.currentCalendarId)\n" +
                                "進捗: \(progress.fetchedRanges)/\(progress.totalRanges)\n" +
                                "取得: \(progress.totalUpserted)件"
                        } else {
                            recoveryProgressText = "イベント取得中..."
                        }
                    case .rebuildingIndexes:
                        recoveryProgressText = "インデックスを再構築中..."
                    case .completed:
                        recoveryProgressText = "復旧が完了しました ✓\n" +
                            "取得: \(progress.totalUpserted)件"
                    case .failed:
                        recoveryProgressText = "復旧に失敗しました: \(progress.errorMessage ?? "不明なエラー")"
                    }
                }
            }
        } catch is CancellationError {
            recoveryProgressText = "復旧がキャンセルされました"
        } catch {
            recoveryProgressText = "復旧に失敗しました: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }

}
