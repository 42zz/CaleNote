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
            Section {
                if auth.isAuthenticated {
                    Text(L10n.tr("settings.google.logged_in", auth.userEmail ?? L10n.tr("common.unknown")))
                    Button(L10n.tr("settings.google.reauthenticate")) {
                        Task {
                            do {
                                try await auth.signIn()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .accessibilityLabel(L10n.tr("settings.google.reauthenticate"))
                    .accessibilityHint(L10n.tr("settings.google.reauthenticate.hint"))
                    Button(L10n.tr("settings.google.sign_out")) {
                        auth.signOut()
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel(L10n.tr("settings.google.sign_out"))
                    .accessibilityHint(L10n.tr("settings.google.sign_out.hint"))
                } else {
                    Button(L10n.tr("settings.google.sign_in")) {
                        Task {
                            do {
                                try await auth.signIn()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .accessibilityLabel(L10n.tr("auth.google.sign_in"))
                    .accessibilityHint(L10n.tr("auth.google.sign_in.hint"))
                }
            } header: {
                Text(L10n.tr("settings.google_account"))
            }
            
            Section {
                TextField(L10n.tr("settings.calendar.target_id.placeholder"), text: $targetCalendarId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(L10n.tr("settings.calendar.target_id.accessibility"))
                
                Text(L10n.tr("settings.calendar.target_id.current", targetCalendarId))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.tr("settings.calendar"))
            }
            
            Section {
                Stepper(L10n.tr("settings.sync_window.past", pastDays), value: $pastDays, in: 1...365)
                Stepper(L10n.tr("settings.sync_window.future", futureDays), value: $futureDays, in: 1...365)
            } header: {
                Text(L10n.tr("settings.sync_window"))
            }

            Section {
                if failedEntries.isEmpty {
                    Text(L10n.tr("settings.sync_failures.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    Button(L10n.tr("settings.sync_failures.retry")) {
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
            } header: {
                Text(L10n.tr("settings.sync_failures"))
            }

            Section {
                Picker(L10n.tr("settings.display.week_start"), selection: $weekStartDay) {
                    Text(L10n.tr("weekday.sunday")).tag(0)
                    Text(L10n.tr("weekday.monday")).tag(1)
                }
                Toggle(L10n.tr("settings.display.show_tags"), isOn: $timelineShowTags)
                Toggle(L10n.tr("settings.display.confirm_delete"), isOn: $confirmDeleteEntry)
            } header: {
                Text(L10n.tr("settings.display"))
            }

            Section {
                Toggle(L10n.tr("settings.trash.enable"), isOn: $trashEnabled)
                Picker(L10n.tr("settings.trash.retention"), selection: $trashRetentionDays) {
                    ForEach(TrashSettings.shared.retentionOptions) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .disabled(!trashEnabled)
                Toggle(L10n.tr("settings.trash.auto_purge"), isOn: $trashAutoPurgeEnabled)
                    .disabled(!trashEnabled)
                NavigationLink(L10n.tr("settings.trash.open")) {
                    TrashView()
                }
            } header: {
                Text(L10n.tr("settings.trash"))
            }

            Section {
                NavigationLink(L10n.tr("settings.tags.manage")) {
                    TagsView()
                }
            } header: {
                Text(L10n.tr("settings.tags"))
            }

            Section {
                HStack {
                    Text(L10n.tr("settings.data.integrity"))
                    Spacer()
                    if let integrityStatus {
                        Text(integrityStatus ? L10n.tr("settings.data.integrity.ok") : L10n.tr("settings.data.integrity.warning"))
                            .foregroundStyle(integrityStatus ? .green : .red)
                    } else {
                        Text(L10n.tr("settings.data.integrity.unchecked"))
                            .foregroundStyle(.secondary)
                    }
                }
                Button(L10n.tr("settings.data.integrity.check")) {
                    integrityStatus = recoveryService.checkIntegrity(modelContext: modelContext)
                }
                Button(L10n.tr("settings.data.rebuild")) {
                    showRecoveryConfirm = true
                }
                .disabled(recoveryService.isRecovering)
                Button(L10n.tr("settings.data.clear_cache")) {
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
            } header: {
                Text(L10n.tr("settings.data_management"))
            }
            
            Section {
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
                        Text(L10n.tr("settings.actions.force_full_sync"))
                    }
                }
                .disabled(syncService.isSyncing)
                .accessibilityLabel(L10n.tr("settings.actions.force_full_sync"))
                .accessibilityHint(L10n.tr("settings.actions.force_full_sync.hint"))
                
                Button(L10n.tr("settings.actions.reset_tokens")) {
                    syncService.resetSyncTokens()
                }
                .accessibilityLabel(L10n.tr("settings.actions.reset_tokens"))
                .accessibilityHint(L10n.tr("settings.actions.reset_tokens.hint"))

                Button(L10n.tr("settings.actions.show_onboarding")) {
                    showOnboarding = true
                }
                .accessibilityLabel(L10n.tr("settings.actions.show_onboarding"))
                .accessibilityHint(L10n.tr("settings.actions.show_onboarding.hint"))
            } header: {
                Text(L10n.tr("settings.actions"))
            }

            Section {
                Text(L10n.tr("settings.app_info.version", appVersion))
                Text(L10n.tr("settings.app_info.build", buildNumber))
                Text(L10n.tr("settings.app_info.privacy_policy"))
                Text(L10n.tr("settings.app_info.terms"))
            } header: {
                Text(L10n.tr("settings.app_info"))
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(L10n.tr("settings.title"))
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
            L10n.tr("settings.data.rebuild.confirm"),
            isPresented: $showRecoveryConfirm
        ) {
            Button(L10n.tr("settings.data.rebuild.confirm.action"), role: .destructive) {
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
            Text(L10n.tr("settings.data.rebuild.confirm.message"))
        }
        .confirmationDialog(
            L10n.tr("settings.data.clear_cache.confirm"),
            isPresented: $showClearCacheConfirm
        ) {
            Button(L10n.tr("common.delete"), role: .destructive) {
                do {
                    try recoveryService.clearLocalData(modelContext: modelContext)
                    searchIndex.rebuildIndex(modelContext: modelContext)
                    relatedIndex.rebuildIndex(modelContext: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert(L10n.tr("settings.data.rebuild.complete"), isPresented: $showRecoveryCompleteAlert) {
            Button(L10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(L10n.tr("settings.data.rebuild.complete.message"))
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(auth)
                .environmentObject(calendarListService)
        }
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.tr("common.unknown")
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.tr("common.unknown")
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
                    L10n.tr("trash.empty.title"),
                    systemImage: "trash",
                    description: Text(L10n.tr("trash.empty.description"))
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
                                    Label(L10n.tr("trash.restore"), systemImage: "arrow.uturn.left")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    purge(entry)
                                } label: {
                                    Label(L10n.tr("trash.permanently_delete"), systemImage: "trash.slash")
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
        .navigationTitle(L10n.tr("trash.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .bottomBar) {
                Button(L10n.tr("trash.restore_selection")) {
                    showRestoreSelectionConfirm = true
                }
                .disabled(selection.isEmpty || isProcessing)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showPurgeSelectionConfirm = true
                } label: {
                    Text(L10n.tr("trash.delete_selection"))
                }
                .disabled(selection.isEmpty || isProcessing)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showPurgeAllConfirm = true
                } label: {
                    Text(L10n.tr("trash.empty.action"))
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
        .alert(L10n.tr("common.action_failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(L10n.tr("trash.empty.confirm"), isPresented: $showPurgeAllConfirm) {
            Button(L10n.tr("trash.empty.action"), role: .destructive) {
                purgeAll()
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("common.irreversible"))
        }
        .confirmationDialog(L10n.tr("trash.restore_selection.confirm"), isPresented: $showRestoreSelectionConfirm) {
            Button(L10n.tr("trash.restore")) {
                restoreSelection()
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("trash.restore_selection.message"))
        }
        .confirmationDialog(L10n.tr("trash.delete_selection.confirm"), isPresented: $showPurgeSelectionConfirm) {
            Button(L10n.tr("trash.permanently_delete"), role: .destructive) {
                purgeSelection()
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("common.irreversible"))
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
        let retentionText = L10n.tr("trash.retention", L10n.number(trashRetentionDays))
        let autoText = trashAutoPurgeEnabled ? L10n.tr("trash.auto_purge.on") : L10n.tr("trash.auto_purge.off")
        return L10n.tr("common.bullet_separated", retentionText, autoText)
    }

    private func deletedDateText(for entry: ScheduleEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = entry.deletedAt ?? entry.updatedAt
        return L10n.tr("trash.deleted_at", formatter.string(from: date))
    }

    private func remainingText(for entry: ScheduleEntry) -> String {
        let deletedAt = entry.deletedAt ?? entry.updatedAt
        let settings = TrashSettings.shared
        let remaining = settings.remainingDays(from: deletedAt)
        if remaining == 0 {
            return L10n.tr("trash.expired")
        }
        let key = remaining == 1 ? "trash.remaining_days.singular" : "trash.remaining_days.plural"
        return L10n.tr(key, L10n.number(remaining))
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
