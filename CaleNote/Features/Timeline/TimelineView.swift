//
//  TimelineView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

/// メイン画面のタイムラインビュー
struct TimelineView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService
    @EnvironmentObject private var calendarListService: CalendarListService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Query

    /// 全スケジュールエントリー
    @Query(
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
        let calendar = Calendar.current
        return Set(filteredEntries.map { calendar.startOfDay(for: $0.startAt) })
    }

    /// 日付でグループ化されたエントリー（新しい日付が上）
    private var groupedEntries: [(date: Date, entries: [ScheduleEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.startAt)
        }

        return grouped
            .map { (date: $0.key, entries: $0.value) }
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
                "エントリーを削除しますか？",
                isPresented: $showDeleteConfirm
            ) {
                Button("削除", role: .destructive) {
                    if let entry = entryPendingDelete {
                        deleteEntry(entry)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    entryPendingDelete = nil
                }
            } message: {
                Text("この操作は取り消せません。")
            }
            .alert("操作に失敗しました", isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionErrorMessage ?? "")
            }
            .onAppear {
                // 今日の日付を更新
                today = Date()
                focusDate = today

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
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(groupedEntries.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.entries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                TimelineRowView(entry: entry, showTags: showTags)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    requestDelete(entry)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    beginEdit(entry)
                                } label: {
                                    Label("編集", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    beginEdit(entry)
                                } label: {
                                    Label("編集", systemImage: "pencil")
                                }
                                .keyboardShortcut(.return, modifiers: [])

                                Button(role: .destructive) {
                                    requestDelete(entry)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                                .keyboardShortcut(.delete, modifiers: [])

                                ShareLink(item: shareText(for: entry)) {
                                    Label("共有", systemImage: "square.and.arrow.up")
                                }

                                Divider()

                                Button("複製 (準備中)") {}
                                    .disabled(true)

                                Button("カレンダー移動 (準備中)") {}
                                    .disabled(true)

                                Button("タグ追加 (準備中)") {}
                                    .disabled(true)
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.2).onEnded { _ in
                                    triggerHaptic(.light)
                                }
                            )
                            .accessibilityAction(named: "編集") {
                                beginEdit(entry)
                            }
                            .accessibilityAction(named: "削除") {
                                requestDelete(entry)
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
        .accessibilityLabel("新規エントリーを作成")
        .accessibilityHint("新しい予定や記録を追加します")
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
                        .accessibilityLabel("同期中")
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(syncService.isSyncing)
            .accessibilityLabel("同期")
            .accessibilityHint("Googleカレンダーと同期します")
            .accessibilityValueText(syncService.isSyncing ? "同期中" : nil)
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
                    actionErrorMessage = "削除に失敗しました: \(error.localizedDescription)"
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
}
