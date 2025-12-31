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

/// メイン画面のタイムラインビュー
struct TimelineView: View {
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

    /// 表示中のセクション日付
    @State private var visibleSectionDates: Set<Date> = []

    /// ScrollViewReader のプロキシ参照
    @State private var scrollProxy: ScrollViewProxy?

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
            .sheet(isPresented: $showSearchView) {
                SearchView()
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
            .onChange(of: syncService.lastSyncError) { _, newValue in
                guard newValue != nil else { return }
                UIAccessibility.post(notification: .announcement, argument: "同期に失敗しました")
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
                            .accessibilityLabel("同期中")
                        Text("Google Calendar からデータを取得中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLiveRegion(.polite)
                        Text("初回同期には少し時間がかかる場合があります")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
            } else if isCalendarSelectionEmpty {
                EmptyStateView(
                    title: "カレンダーを選択してください",
                    message: "表示するカレンダーが選択されていません。",
                    systemImage: "calendar.badge.exclamationmark",
                    detail: "サイドバーで表示するカレンダーを選択できます。",
                    primaryActionTitle: "サイドバーを開く",
                    primaryAction: { onSidebarButtonTap?() },
                    secondaryActionTitle: "設定を開く",
                    secondaryAction: { NotificationCenter.default.post(name: .openSettings, object: nil) }
                )
            } else if let errorMessage = syncErrorMessage, filteredEntries.isEmpty {
                syncErrorState(message: errorMessage)
            } else if filteredEntries.isEmpty {
                EmptyStateView(
                    title: "まだエントリーがありません",
                    message: "予定やメモを追加して、タイムラインを作成しましょう。",
                    systemImage: "note.text",
                    detail: "右下の + からも作成できます。",
                    primaryActionTitle: "エントリーを作成",
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
                        ForEach(section.entries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                TimelineRowView(entry: entry, showTags: showTags)
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
            title: "同期エラーが発生しました",
            message: message,
            systemImage: "exclamationmark.triangle",
            detail: "通信環境を確認して再試行してください。",
            primaryActionTitle: "再試行",
            primaryAction: {
                Task { await refreshTimeline() }
            },
            secondaryActionTitle: "サポートに連絡",
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
                Text("同期に失敗しました")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("再試行") {
                    Task { await refreshTimeline() }
                }
                .buttonStyle(.bordered)

                Button("サポートに連絡") {
                    guard let url = URL(string: "mailto:feedback@calenote.app") else { return }
                    openURL(url)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("同期に失敗しました")
    }
}
