//
//  TimelineView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI
import SwiftData

/// メイン画面のタイムラインビュー
struct TimelineView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService
    @EnvironmentObject private var calendarListService: CalendarListService

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
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(groupedEntries.enumerated()), id: \.offset) { index, section in
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
                }
            }
            .listStyle(.plain)
            .onAppear {
                scrollProxy = proxy
                scrollToToday()
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
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(syncService.isSyncing)
        }
    }

    // MARK: - Helper Methods

    /// 今日のセクションかどうか判定
    private func isTodaySection(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(date, inSameDayAs: today)
    }

    /// 今日のセクションにスクロール
    private func scrollToToday() {
        today = Date()
        focusDate = today

        scrollToDate(today)
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
            withAnimation {
                proxy.scrollTo(targetSection.date, anchor: .top)
            }
        }
    }
}
