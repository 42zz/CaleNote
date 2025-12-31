//
//  TimelineView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import SwiftData
import SwiftUI
import UIKit

#if canImport(UIKit)
import UIKit
#endif

/// メイン画面のタイムラインビュー
struct TimelineView: View {
    private struct TimelineDisplayEntry: Identifiable {
        let id: String
        let entry: ScheduleEntry
        let displayDate: Date
    }

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService
    @EnvironmentObject private var calendarListService: CalendarListService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    // MARK: - Query

    /// 全スケジュールエントリー
    @Query(
        filter: #Predicate<ScheduleEntry> { entry in
            entry.isDeleted == false
        },
        sort: \ScheduleEntry.startAt,
        order: .forward
    ) private var allEntries: [ScheduleEntry]

    // MARK: - Properties

    /// サイドバーボタンを表示するか
    var showSidebarButton: Bool = false

    /// サイドバーボタンがタップされた時のコールバック
    var onSidebarButtonTap: (() -> Void)?

    // MARK: - State

    /// 今日の日付
    @State private var today = Date()

    /// 検索画面表示フラグ
    @State private var showSearchView = false

    /// 新規エントリー作成シート表示フラグ
    @State private var showNewEntrySheet = false

    /// フォーカス日付（月表示で使用）
    @State private var focusDate = Date()

    /// 表示設定
    @AppStorage("timelineShowTags") private var showTags = true
    @AppStorage("confirmDeleteEntry") private var confirmDeleteEntry = true
    @AppStorage("trashEnabled") private var trashEnabled = TrashSettings.shared.isEnabled
    @AppStorage("trashAutoPurgeEnabled") private var trashAutoPurgeEnabled = TrashSettings.shared.autoPurgeEnabled

    /// 表示中のセクション日付
    @State private var visibleSectionDates: Set<Date> = []

    /// ScrollViewReader のプロキシ参照
    @State private var scrollProxy: ScrollViewProxy?

    /// 編集対象のエントリー
    @State private var entryToEdit: ScheduleEntry?

    /// 削除対象のエントリー
    @State private var entryPendingDelete: ScheduleEntry?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var actionErrorMessage: String?

    // MARK: - Computed Properties

    /// 表示対象のカレンダーIDセット
    private var visibleCalendarIds: Set<String> {
        calendarListService.visibleCalendarIds
    }

    /// フィルタリングされたエントリー
    private var filteredEntries: [ScheduleEntry] {
        // カレンダーリストが空の場合（未同期）は全エントリーを表示
        guard !calendarListService.calendars.isEmpty else {
            return allEntries
        }

        return allEntries.filter { entry in
            // calendarIdがnilの場合は表示（レガシーデータ対応）
            guard let calendarId = entry.calendarId else {
                return true
            }
            return visibleCalendarIds.contains(calendarId)
        }
    }

    /// エントリー存在日の集合（startOfDay）
    private var entryDates: Set<Date> {
        Set(timelineDisplayEntries.map { $0.displayDate })
    }

    /// 初回同期中かどうか
    private var isInitialSyncing: Bool {
        allEntries.isEmpty && (syncService.isSyncing || calendarListService.isSyncing)
    }

    /// カレンダー未選択状態かどうか
    private var isCalendarSelectionEmpty: Bool {
        !calendarListService.calendars.isEmpty && visibleCalendarIds.isEmpty
    }

    /// 同期エラーメッセージ
    private var syncErrorMessage: String? {
        if let error = syncService.lastSyncError ?? calendarListService.lastError {
            return error.localizedDescription
        }
        return nil
    }

    /// 表示用に展開したエントリー
    private var timelineDisplayEntries: [TimelineDisplayEntry] {
        let calendar = Calendar.current
        var result: [TimelineDisplayEntry] = []
        result.reserveCapacity(filteredEntries.count)

        for entry in filteredEntries {
            if entry.isAllDay {
                let span = entry.allDaySpan(using: calendar)
                for offset in 0..<span.dayCount {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: span.startDay) else { continue }
                    result.append(
                        TimelineDisplayEntry(
                            id: displayEntryId(for: entry, date: day),
                            entry: entry,
                            displayDate: day
                        )
                    )
                }
            } else {
                let day = calendar.startOfDay(for: entry.startAt)
                result.append(
                    TimelineDisplayEntry(
                        id: displayEntryId(for: entry, date: day),
                        entry: entry,
                        displayDate: day
                    )
                )
            }
        }

        return result
    }

    /// 日付でグループ化されたエントリー（新しい日付が上）
    private var groupedEntries: [(date: Date, entries: [TimelineDisplayEntry])] {
        let grouped = Dictionary(grouping: timelineDisplayEntries) { $0.displayDate }

        return grouped
            .map { (date: $0.key, entries: sortDisplayEntries($0.value)) }
            .sorted { $0.date > $1.date } // 新しい日付が先
    }

    /// 今日のセクションのインデックス
    private var todaySectionIndex: Int? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)

        return groupedEntries.firstIndex { section in
            calendar.isDate(section.date, inSameDayAs: todayStart)
        }
    }

    private var deleteLabel: String {
        trashEnabled ? L10n.tr("trash.move_to_trash") : L10n.tr("common.delete")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TopBarView(
                    showsSidebarButton: showSidebarButton,
                    onSidebarTap: {
                        onSidebarButtonTap?()
                    },
                    showSearch: $showSearchView,
                    focusDate: $focusDate,
                    scrollToToday: scrollToToday,
                    entryDates: entryDates,
                    onSelectDate: { date in
                        focusDate = date
                        scrollToDate(date)
                    }
                )

                Divider()

                ZStack(alignment: .bottomTrailing) {
                    // タイムラインリスト
                    timelineList

                    // FAB ボタン
                    fabButton
                }
            }
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showNewEntrySheet) {
                JournalEditorView()
                    .environmentObject(syncService)
            }
            .sheet(isPresented: Binding(
                get: { entryToEdit != nil },
                set: { if !$0 { entryToEdit = nil } }
            )) {
                if let entry = entryToEdit {
                    JournalEditorView(entry: entry, initialDate: entry.startAt)
                        .environmentObject(syncService)
                }
            }
            .sheet(isPresented: $showSearchView) {
                SearchView()
            }
            .confirmationDialog(
                trashEnabled ? L10n.tr("timeline.delete.confirm.trash") : L10n.tr("timeline.delete.confirm.delete"),
                isPresented: $showDeleteConfirm
            ) {
                Button(trashEnabled ? L10n.tr("trash.move_to_trash") : L10n.tr("common.delete"), role: .destructive) {
                    if let entry = entryPendingDelete {
                        deleteEntry(entry)
                    }
                }
                Button(L10n.tr("common.cancel"), role: .cancel) {
                    entryPendingDelete = nil
                }
            } message: {
                Text(trashEnabled ? L10n.tr("trash.restore_hint") : L10n.tr("common.irreversible"))
            }
            .alert(L10n.tr("common.action_failed"), isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )) {
                Button(L10n.tr("common.ok"), role: .cancel) {}
            } message: {
                Text(actionErrorMessage ?? "")
            }
            .onAppear {
                // 今日の日付を更新
                today = Date()
                focusDate = today

                if trashAutoPurgeEnabled {
                    try? syncService.cleanupExpiredTrashEntries()
                }

                // 定期的な同期を開始（必要に応じて）
                syncService.startBackgroundSync()
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    refreshForDayChange(shouldScroll: true)
                    Task { await syncService.performForegroundSync() }
                    syncService.startBackgroundSync()
                case .inactive, .background:
                    syncService.stopBackgroundSync()
                @unknown default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshForDayChange(shouldScroll: true)
            }
            .onChange(of: syncService.lastSyncError) { _, newValue in
                guard newValue != nil else { return }
                UIAccessibility.post(notification: .announcement, argument: L10n.tr("sync.failed"))
            }
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        Group {
            if isInitialSyncing {
                ZStack {
                    TimelineSkeletonView()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.1)
                            .accessibilityLabel(L10n.tr("sync.in_progress"))
                        Text(L10n.tr("timeline.syncing.message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLiveRegion(.polite)
                        Text(L10n.tr("timeline.syncing.detail"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
            } else if isCalendarSelectionEmpty {
                EmptyStateView(
                    title: L10n.tr("timeline.empty.calendar.title"),
                    message: L10n.tr("timeline.empty.calendar.message"),
                    systemImage: "calendar.badge.exclamationmark",
                    detail: L10n.tr("timeline.empty.calendar.detail"),
                    primaryActionTitle: L10n.tr("timeline.empty.calendar.primary_action"),
                    primaryAction: { onSidebarButtonTap?() },
                    secondaryActionTitle: L10n.tr("timeline.empty.calendar.secondary_action"),
                    secondaryAction: { NotificationCenter.default.post(name: .openSettings, object: nil) }
                )
            } else if let errorMessage = syncErrorMessage, filteredEntries.isEmpty {
                syncErrorState(message: errorMessage)
            } else if filteredEntries.isEmpty {
                EmptyStateView(
                    title: L10n.tr("timeline.empty.entries.title"),
                    message: L10n.tr("timeline.empty.entries.message"),
                    systemImage: "note.text",
                    detail: L10n.tr("timeline.empty.entries.detail"),
                    primaryActionTitle: L10n.tr("timeline.empty.entries.primary_action"),
                    primaryAction: { showNewEntrySheet = true }
                )
            } else {
                timelineListContent
            }
        }
    }

    private var timelineListContent: some View {
        ScrollViewReader { proxy in
            List {
                if let errorMessage = syncErrorMessage {
                    Section {
                        syncErrorBanner(message: errorMessage)
                    }
                }

                ForEach(Array(groupedEntries.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.entries) { displayEntry in
                            NavigationLink {
                                EntryDetailView(entry: displayEntry.entry)
                            } label: {
                                TimelineRowView(
                                    entry: displayEntry.entry,
                                    showTags: showTags,
                                    displayDate: displayEntry.displayDate
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    requestDelete(displayEntry.entry)
                                } label: {
                                    Label(deleteLabel, systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    beginEdit(displayEntry.entry)
                                } label: {
                                    Label(L10n.tr("common.edit"), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    beginEdit(displayEntry.entry)
                                } label: {
                                    Label(L10n.tr("common.edit"), systemImage: "pencil")
                                }
                                .keyboardShortcut(.return, modifiers: [])

                                Button(role: .destructive) {
                                    requestDelete(displayEntry.entry)
                                } label: {
                                    Label(deleteLabel, systemImage: "trash")
                                }
                                .keyboardShortcut(.delete, modifiers: [])

                                ShareLink(item: shareText(for: displayEntry.entry)) {
                                    Label(L10n.tr("common.share"), systemImage: "square.and.arrow.up")
                                }

                                Divider()

                                Button(L10n.tr("common.duplicate_coming_soon")) {}
                                    .disabled(true)

                                Button(L10n.tr("timeline.move_calendar_coming_soon")) {}
                                    .disabled(true)

                                Button(L10n.tr("timeline.add_tag_coming_soon")) {}
                                    .disabled(true)
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.2).onEnded { _ in
                                    triggerHaptic(.light)
                                }
                            )
                            .accessibilityAction(named: L10n.tr("common.edit")) {
                                beginEdit(displayEntry.entry)
                            }
                            .accessibilityAction(named: L10n.tr("common.delete")) {
                                requestDelete(displayEntry.entry)
                            }
                        }
                    } header: {
                        DateSectionHeader(
                            date: section.date,
                            isToday: isTodaySection(section.date)
                        )
                    }
                    .id(section.date)
                    .onAppear {
                        visibleSectionDates.insert(section.date)
                    }
                    .onDisappear {
                        visibleSectionDates.remove(section.date)
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("timelineList")
            .refreshable {
                await refreshTimeline()
            }
            .onAppear {
                // 初回表示時に今日のセクションにスクロール
                scrollProxy = proxy
                scrollToToday(forceToday: true)
            }
        }
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button {
            showNewEntrySheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel(L10n.tr("timeline.new_entry"))
        .accessibilityHint(L10n.tr("timeline.new_entry.hint"))
        .accessibilityIdentifier("newEntryFab")
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 同期ボタン
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task {
                    do {
                        try await syncService.performFullSync()
                    } catch {
                        print("Sync failed: \(error)")
                    }
                }
            } label: {
                if syncService.isSyncing {
                    ProgressView()
                        .accessibilityLabel(L10n.tr("sync.in_progress"))
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(syncService.isSyncing)
            .accessibilityLabel(L10n.tr("sync.title"))
            .accessibilityHint(L10n.tr("sync.hint"))
            .accessibilityValueText(syncService.isSyncing ? L10n.tr("sync.in_progress") : nil)
        }
    }

    // MARK: - Helper Methods

    /// 今日のセクションかどうか判定
    private func isTodaySection(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(date, inSameDayAs: today)
    }

    /// 今日のセクションにスクロール
    private func scrollToToday(forceToday: Bool) {
        today = Date()
        focusDate = today
        guard let proxy = scrollProxy else { return }
        guard let todaySection = groupedEntries.first(where: { isTodaySection($0.date) }) else {
            return
        }

        let shouldScrollToTop = !forceToday && visibleSectionDates.contains(todaySection.date)
        let targetDate = shouldScrollToTop ? groupedEntries.first?.date : todaySection.date
        guard let targetDate else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AccessibilityAnimation.perform(reduceMotion: reduceMotion) {
                proxy.scrollTo(targetDate, anchor: .top)
            }
        }
    }

    /// 指定日のセクションにスクロール
    private func scrollToDate(_ date: Date) {
        guard let proxy = scrollProxy else { return }

        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        guard let targetSection = groupedEntries.first(where: {
            calendar.isDate($0.date, inSameDayAs: targetDate)
        }) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AccessibilityAnimation.perform(reduceMotion: reduceMotion) {
                proxy.scrollTo(targetSection.date, anchor: .top)
            }
        }
    }

    private func beginEdit(_ entry: ScheduleEntry) {
        triggerHaptic(.light)
        entryToEdit = entry
    }

    private func requestDelete(_ entry: ScheduleEntry) {
        triggerHaptic(.medium)
        if confirmDeleteEntry {
            entryPendingDelete = entry
            showDeleteConfirm = true
        } else {
            deleteEntry(entry)
        }
    }

    private func deleteEntry(_ entry: ScheduleEntry) {
        if isDeleting { return }
        isDeleting = true
        actionErrorMessage = nil

        Task {
            do {
                try await syncService.deleteEntry(entry)
                await MainActor.run {
                    isDeleting = false
                    entryPendingDelete = nil
                }
            } catch {
                await MainActor.run {
                    actionErrorMessage = L10n.tr("timeline.delete.failed", error.localizedDescription)
                    isDeleting = false
                }
            }
        }
    }

    private func shareText(for entry: ScheduleEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = entry.isAllDay ? .none : .short
        let dateText = formatter.string(from: entry.startAt)
        var parts = [entry.title, dateText]
        if let body = entry.body, !body.isEmpty {
            parts.append(body)
        }
        return parts.joined(separator: "\n")
    }

    private func displayEntryId(for entry: ScheduleEntry, date: Date) -> String {
        let baseId = entry.googleEventId
            ?? "\(entry.createdAt.timeIntervalSince1970)-\(entry.startAt.timeIntervalSince1970)-\(entry.title.hashValue)"
        return "\(baseId)-\(Int(date.timeIntervalSince1970))"
    }

    private func sortDisplayEntries(_ entries: [TimelineDisplayEntry]) -> [TimelineDisplayEntry] {
        let calendar = Calendar.current
        return entries.sorted { lhs, rhs in
            if lhs.entry.isAllDay != rhs.entry.isAllDay {
                return lhs.entry.isAllDay && !rhs.entry.isAllDay
            }

            if lhs.entry.isAllDay && rhs.entry.isAllDay {
                if lhs.entry.title != rhs.entry.title {
                    return lhs.entry.title.localizedStandardCompare(rhs.entry.title) == .orderedAscending
                }
                return lhs.entry.createdAt < rhs.entry.createdAt
            }

            if lhs.entry.startAt != rhs.entry.startAt {
                return lhs.entry.startAt < rhs.entry.startAt
            }

            if lhs.entry.title != rhs.entry.title {
                return lhs.entry.title.localizedStandardCompare(rhs.entry.title) == .orderedAscending
            }

            return calendar.compare(lhs.displayDate, to: rhs.displayDate, toGranularity: .day) == .orderedAscending
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
#endif
    }

    /// 日付変更時の更新処理
    private func refreshForDayChange(shouldScroll: Bool) {
        let now = Date()
        let calendar = Calendar.current
        let didChange = !calendar.isDate(now, inSameDayAs: today)
        today = now
        focusDate = today

        if didChange, shouldScroll {
            scrollToToday(forceToday: true)
        }
    }

    private func refreshTimeline() async {
        await calendarListService.syncCalendarList()
        try? await syncService.performFullSync()
    }

    private func syncErrorState(message: String) -> some View {
        EmptyStateView(
            title: L10n.tr("sync.error.title"),
            message: message,
            systemImage: "exclamationmark.triangle",
            detail: L10n.tr("sync.error.detail"),
            primaryActionTitle: L10n.tr("common.retry"),
            primaryAction: {
                Task { await refreshTimeline() }
            },
            secondaryActionTitle: L10n.tr("support.contact"),
            secondaryAction: {
                guard let url = URL(string: "mailto:feedback@calenote.app") else { return }
                openURL(url)
            }
        )
    }

    private func syncErrorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(L10n.tr("sync.failed"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(L10n.tr("common.retry")) {
                    Task { await refreshTimeline() }
                }
                .buttonStyle(.bordered)

                Button(L10n.tr("support.contact")) {
                    guard let url = URL(string: "mailto:feedback@calenote.app") else { return }
                    openURL(url)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("sync.failed"))
    }
}
