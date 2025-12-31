//
//  MainNavigationView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import SwiftData
import SwiftUI

/// メインナビゲーションビュー
/// サイドバーとタイムラインを統合したメインUIコンテナ
struct MainNavigationView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Query

    @Query(
        sort: \ScheduleEntry.startAt,
        order: .forward
    ) private var allEntries: [ScheduleEntry]

    // MARK: - State

    /// サイドバー表示フラグ
    @State private var showSidebar = false

    /// 検索画面表示フラグ
    @State private var showSearchView = false

    /// 新規エントリー作成シート表示フラグ
    @State private var showNewEntrySheet = false

    /// フォーカス日付（月表示やスクロール位置で使用）
    @State private var focusDate = Date()

    /// 今日の日付
    @State private var today = Date()

    /// 表示設定
    @AppStorage("timelineShowTags") private var showTags = true
    @AppStorage("showGoogleCalendarEvents") private var showGoogleCalendarEvents = true
    @AppStorage("showCaleNoteEntries") private var showCaleNoteEntries = true

    /// ScrollViewReader のプロキシ参照
    @State private var scrollProxy: ScrollViewProxy?

    /// 表示中のセクション日付
    @State private var visibleSectionDates: Set<Date> = []

    // MARK: - Computed Properties

    /// フィルタリングされたエントリー
    private var filteredEntries: [ScheduleEntry] {
        allEntries.filter { entry in
            if entry.managedByCaleNote {
                return showCaleNoteEntries
            } else {
                return showGoogleCalendarEvents
            }
        }
    }

    /// 日付でグループ化されたエントリー（新しい日付が上）
    private var groupedEntries: [(date: Date, entries: [ScheduleEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.startAt)
        }

        return grouped
            .map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    /// エントリー存在日の集合（startOfDay）
    private var entryDates: Set<Date> {
        let calendar = Calendar.current
        return Set(filteredEntries.map { calendar.startOfDay(for: $0.startAt) })
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // メインコンテンツ
            VStack(spacing: 0) {
                // トップバー
                TopBarView(
                    showsSidebarButton: true,
                    onSidebarTap: {
                        showSidebar = true
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

                // タイムラインリスト
                timelineList
            }

            // FAB ボタン
            fabButton
        }
        .sheet(isPresented: $showSidebar) {
            SidebarView()
                .environmentObject(auth)
                .environmentObject(syncService)
        }
        .sheet(isPresented: $showNewEntrySheet) {
            JournalEditorView(initialDate: focusDate)
                .environmentObject(syncService)
        }
        .sheet(isPresented: $showSearchView) {
            SearchView()
        }
        .onAppear {
            today = Date()
            focusDate = today
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
            .onAppear {
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
    }

    // MARK: - Helper Methods

    /// 今日のセクションかどうか判定
    private func isTodaySection(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: today)
    }

    /// 今日のセクションにスクロール
    private func scrollToToday() {
        scrollToToday(forceToday: false)
    }

    /// 今日のセクションにスクロール（強制オプション）
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
}

// Preview disabled due to complex dependency injection requirements
