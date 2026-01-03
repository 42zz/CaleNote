import GoogleSignIn
import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService
    @EnvironmentObject private var searchIndex: SearchIndexService
    @EnvironmentObject private var relatedIndex: RelatedEntriesIndexService
    @EnvironmentObject private var calendarListService: CalendarListService
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<ScheduleEntry> { entry in
            entry.syncStatus == "failed" && entry.isDeleted == false
        },
        sort: \ScheduleEntry.startAt,
        order: .reverse
    ) private var failedEntries: [ScheduleEntry]

    @StateObject private var recoveryService = DataRecoveryService()

    @State private var errorMessage: String?
    @State private var integrityStatus: Bool?
    @State private var showRecoveryConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showRecoveryCompleteAlert = false
    @State private var showOnboarding = false
    
    // Settings
    @AppStorage("targetCalendarId") private var targetCalendarId: String = CalendarSettings.shared.targetCalendarId
    @AppStorage("syncWindowDaysPast") private var pastDays: Int = CalendarSettings.shared.syncWindowDaysPast
    @AppStorage("syncWindowDaysFuture") private var futureDays: Int = CalendarSettings.shared.syncWindowDaysFuture
    @AppStorage("displayWeekStartDay") private var weekStartDay: Int = DisplaySettings.defaultWeekStartDay
    @AppStorage("timelineShowTags") private var timelineShowTags = true
    @AppStorage("confirmDeleteEntry") private var confirmDeleteEntry = true
    @AppStorage("trashEnabled") private var trashEnabled = TrashSettings.shared.isEnabled
    @AppStorage("trashRetentionDays") private var trashRetentionDays = TrashSettings.shared.retentionDays
    @AppStorage("trashAutoPurgeEnabled") private var trashAutoPurgeEnabled = TrashSettings.shared.autoPurgeEnabled

    var body: some View {
        Form {
            Section("Google Account") {
                if auth.isAuthenticated {
                    Text("Logged in as: \(auth.userEmail ?? "Unknown")")
                    Button("Reauthenticate") {
                        Task {
                            do {
                                try await auth.signIn()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .accessibilityLabel("再認証")
                    .accessibilityHint("Googleアカウントの再認証を行います")
                    Button("Sign Out") {
                        auth.signOut()
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("サインアウト")
                    .accessibilityHint("Googleアカウントからサインアウトします")
                } else {
                    Button("Sign In with Google") {
                        Task {
                            do {
                                try await auth.signIn()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .accessibilityLabel("Googleでサインイン")
                    .accessibilityHint("Googleアカウントでサインインします")
                }
            }
            
            Section("Calendar Settings") {
                TextField("Target Calendar ID", text: $targetCalendarId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("書き込み先カレンダーID")
                
                Text("Current target for writes: \(targetCalendarId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Sync Window") {
                Stepper("Past: \(pastDays) days", value: $pastDays, in: 1...365)
                Stepper("Future: \(futureDays) days", value: $futureDays, in: 1...365)
            }

            Section("Sync Failures") {
                if failedEntries.isEmpty {
                    Text("同期失敗はありません")
                        .foregroundStyle(.secondary)
                } else {
                    Button("失敗エントリーを再送") {
                        Task {
                            do {
                                try await syncService.retryFailedSyncs()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }

                    ForEach(failedEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.body)
                            Text(entry.startAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Display Settings") {
                Picker("週の開始曜日", selection: $weekStartDay) {
                    Text("日曜日").tag(0)
                    Text("月曜日").tag(1)
                }
                Toggle("タイムラインにタグを表示", isOn: $timelineShowTags)
                Toggle("削除前に確認する", isOn: $confirmDeleteEntry)
            }

            Section("Trash") {
                Toggle("ゴミ箱を有効にする", isOn: $trashEnabled)
                Picker("保持期間", selection: $trashRetentionDays) {
                    ForEach(TrashSettings.shared.retentionOptions) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .disabled(!trashEnabled)
                Toggle("期限切れを自動削除", isOn: $trashAutoPurgeEnabled)
                    .disabled(!trashEnabled)
                NavigationLink("ゴミ箱を開く") {
                    TrashView()
                }
            }

            Section("Tags") {
                NavigationLink("タグ管理") {
                    TagsView()
                }
            }

            Section("Data Management") {
                HStack {
                    Text("データ整合性")
                    Spacer()
                    if let integrityStatus {
                        Text(integrityStatus ? "OK" : "破損の可能性")
                            .foregroundStyle(integrityStatus ? .green : .red)
                    } else {
                        Text("未チェック")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("整合性チェック") {
                    integrityStatus = recoveryService.checkIntegrity(modelContext: modelContext)
                }
                Button("ローカルデータを再構築") {
                    showRecoveryConfirm = true
                }
                .disabled(recoveryService.isRecovering)
                Button("ローカルキャッシュを削除") {
                    showClearCacheConfirm = true
                }
                .disabled(recoveryService.isRecovering)

                if recoveryService.isRecovering {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: recoveryService.progress)
                        Text(recoveryService.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Actions") {
                Button {
                    Task {
                        do {
                            try await syncService.performFullSync()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        if syncService.isSyncing {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Force Full Sync")
                    }
                }
                .disabled(syncService.isSyncing)
                .accessibilityLabel("フル同期を実行")
                .accessibilityHint("Googleカレンダーとすべてのデータを再同期します")
                
                Button("Reset Tokens") {
                    syncService.resetSyncTokens()
                }
                .accessibilityLabel("同期トークンをリセット")
                .accessibilityHint("次回の同期で全件取得します")

                Button("オンボーディングを再表示") {
                    showOnboarding = true
                }
                .accessibilityLabel("オンボーディングを再表示")
                .accessibilityHint("初回ガイドを再度確認します")
            }

            Section("Debug & Diagnostics") {
                NavigationLink("クラッシュレポート") {
                    CrashReportsView()
                }
            }

            Section("App Info") {
                Text("Version: \(appVersion)")
                Text("Build: \(buildNumber)")
                Text("Privacy Policy: 未設定")
                Text("Terms of Service: 未設定")
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: targetCalendarId) { _, newValue in
            CalendarSettings.shared.targetCalendarId = newValue
        }
        .onChange(of: pastDays) { _, newValue in
            CalendarSettings.shared.syncWindowDaysPast = newValue
        }
        .onChange(of: futureDays) { _, newValue in
            CalendarSettings.shared.syncWindowDaysFuture = newValue
        }
        .onChange(of: trashEnabled) { _, newValue in
            TrashSettings.shared.isEnabled = newValue
        }
        .onChange(of: trashRetentionDays) { _, newValue in
            TrashSettings.shared.retentionDays = newValue
        }
        .onChange(of: trashAutoPurgeEnabled) { _, newValue in
            TrashSettings.shared.autoPurgeEnabled = newValue
        }
        .confirmationDialog(
            "ローカルデータを再構築しますか？",
            isPresented: $showRecoveryConfirm
        ) {
            Button("再構築", role: .destructive) {
                Task {
                    await recoveryService.recoverFromGoogle(
                        modelContext: modelContext,
                        syncService: syncService,
                        pastDays: recoveryRangePastDays,
                        futureDays: recoveryRangeFutureDays
                    )
                    searchIndex.rebuildIndex(modelContext: modelContext)
                    relatedIndex.rebuildIndex(modelContext: modelContext)
                    if let error = recoveryService.lastError {
                        errorMessage = error.localizedDescription
                    } else {
                        showRecoveryCompleteAlert = true
                    }
                }
            }
        } message: {
            Text("ローカルデータを削除して Google Calendar から再取得します。")
        }
        .confirmationDialog(
            "ローカルキャッシュを削除しますか？",
            isPresented: $showClearCacheConfirm
        ) {
            Button("削除", role: .destructive) {
                do {
                    try recoveryService.clearLocalData(modelContext: modelContext)
                    searchIndex.rebuildIndex(modelContext: modelContext)
                    relatedIndex.rebuildIndex(modelContext: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("復旧完了", isPresented: $showRecoveryCompleteAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ローカルデータの再構築が完了しました。")
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(auth)
                .environmentObject(calendarListService)
        }
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    // MARK: - Recovery Range

    private var recoveryRangePastDays: Int { 36500 }
    private var recoveryRangeFutureDays: Int { 36500 }
}

private struct TrashView: View {
    @EnvironmentObject private var syncService: CalendarSyncService

    @Query(
        filter: #Predicate<ScheduleEntry> { entry in
            entry.isDeleted == true
        },
        sort: [SortDescriptor(\ScheduleEntry.deletedAt, order: .reverse)]
    ) private var trashedEntries: [ScheduleEntry]

    @AppStorage("trashRetentionDays") private var trashRetentionDays = TrashSettings.shared.retentionDays
    @AppStorage("trashAutoPurgeEnabled") private var trashAutoPurgeEnabled = TrashSettings.shared.autoPurgeEnabled

    @State private var selection = Set<ScheduleEntry.ID>()
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showPurgeAllConfirm = false
    @State private var showPurgeSelectionConfirm = false
    @State private var showRestoreSelectionConfirm = false

    var body: some View {
        List(selection: $selection) {
            if trashedEntries.isEmpty {
                ContentUnavailableView(
                    "ゴミ箱は空です",
                    systemImage: "trash",
                    description: Text("削除されたエントリーはここに表示されます。")
                )
            } else {
                Section {
                    ForEach(trashedEntries) { entry in
                        trashRow(entry)
                            .tag(entry.id)
                            .swipeActions(edge: .leading) {
                                Button {
                                    restore(entry)
                                } label: {
                                    Label("復元", systemImage: "arrow.uturn.left")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    purge(entry)
                                } label: {
                                    Label("完全削除", systemImage: "trash.slash")
                                }
                            }
                    }
                } footer: {
                    Text(trashFooterText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("ゴミ箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .bottomBar) {
                Button("選択を復元") {
                    showRestoreSelectionConfirm = true
                }
                .disabled(selection.isEmpty || isProcessing)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showPurgeSelectionConfirm = true
                } label: {
                    Text("選択を完全削除")
                }
                .disabled(selection.isEmpty || isProcessing)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showPurgeAllConfirm = true
                } label: {
                    Text("ゴミ箱を空にする")
                }
                .disabled(trashedEntries.isEmpty || isProcessing)
            }
        }
        .overlay {
            if isProcessing {
                ProgressView()
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("操作に失敗しました", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("ゴミ箱を空にしますか？", isPresented: $showPurgeAllConfirm) {
            Button("空にする", role: .destructive) {
                purgeAll()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .confirmationDialog("選択したエントリーを復元しますか？", isPresented: $showRestoreSelectionConfirm) {
            Button("復元") {
                restoreSelection()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("Google Calendar に再作成します。")
        }
        .confirmationDialog("選択したエントリーを完全削除しますか？", isPresented: $showPurgeSelectionConfirm) {
            Button("完全削除", role: .destructive) {
                purgeSelection()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .onAppear {
            if trashAutoPurgeEnabled {
                try? syncService.cleanupExpiredTrashEntries()
            }
        }
    }

    private func trashRow(_ entry: ScheduleEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.body)
            Text(deletedDateText(for: entry))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(remainingText(for: entry))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var trashFooterText: String {
        let retentionText = "\(trashRetentionDays)日間保持"
        let autoText = trashAutoPurgeEnabled ? "期限切れは自動削除" : "自動削除はオフ"
        return "\(retentionText) ・ \(autoText)"
    }

    private func deletedDateText(for entry: ScheduleEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = entry.deletedAt ?? entry.updatedAt
        return "削除日時: \(formatter.string(from: date))"
    }

    private func remainingText(for entry: ScheduleEntry) -> String {
        let deletedAt = entry.deletedAt ?? entry.updatedAt
        let settings = TrashSettings.shared
        let remaining = settings.remainingDays(from: deletedAt)
        return remaining == 0 ? "期限切れ" : "残り \(remaining) 日"
    }

    private func restore(_ entry: ScheduleEntry) {
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                try await syncService.restoreEntry(entry)
                await MainActor.run {
                    selection.remove(entry.id)
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func purge(_ entry: ScheduleEntry) {
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        do {
            try syncService.purgeEntry(entry)
            selection.remove(entry.id)
            isProcessing = false
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func restoreSelection() {
        if isProcessing { return }
        let targets = selectedEntries()
        guard !targets.isEmpty else { return }
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                for entry in targets {
                    try await syncService.restoreEntry(entry)
                }
                await MainActor.run {
                    selection.removeAll()
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func purgeSelection() {
        if isProcessing { return }
        let targets = selectedEntries()
        guard !targets.isEmpty else { return }
        isProcessing = true
        errorMessage = nil

        do {
            for entry in targets {
                try syncService.purgeEntry(entry)
            }
            selection.removeAll()
            isProcessing = false
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func purgeAll() {
        if isProcessing { return }
        isProcessing = true
        errorMessage = nil
        do {
            try syncService.purgeAllTrashEntries()
            selection.removeAll()
            isProcessing = false
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func selectedEntries() -> [ScheduleEntry] {
        let selectionSet = selection
        return trashedEntries.filter { selectionSet.contains($0.id) }
    }
}
