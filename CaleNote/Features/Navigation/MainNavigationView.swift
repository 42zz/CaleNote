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
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService

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

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // メインコンテンツ
            VStack(spacing: 0) {
                // トップバー
                TopBarView(
                    showSidebar: $showSidebar,
                    showSearch: $showSearchView,
                    focusDate: $focusDate,
                    scrollToToday: scrollToToday
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

    // MARK: - Helper Methods

    /// 今日のセクションかどうか判定
    private func isTodaySection(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: today)
    }

    /// 今日のセクションにスクロール
    private func scrollToToday() {
        today = Date()
        focusDate = today

        guard let proxy = scrollProxy else { return }
        guard let todaySection = groupedEntries.first(where: { isTodaySection($0.date) }) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo(todaySection.date, anchor: .top)
            }
        }
    }
}

// Preview disabled due to complex dependency injection requirements
