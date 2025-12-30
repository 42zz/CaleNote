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

    // MARK: - Query

    /// 全スケジュールエントリー
    @Query(
        sort: \ScheduleEntry.startAt,
        order: .forward
    ) private var allEntries: [ScheduleEntry]

    // MARK: - State

    /// 今日の日付
    @State private var today = Date()

    /// 検索テキスト
    @State private var searchText = ""

    /// 検索バー表示フラグ
    @State private var showSearchBar = false

    /// 新規エントリー作成シート表示フラグ
    @State private var showNewEntrySheet = false

    /// 同期サービス
    @StateObject private var syncService: CalendarSyncService

    // MARK: - Initialization

    init() {
        // NOTE: CalendarSyncService の初期化には modelContext が必要ですが、
        // init 時点では Environment がまだ利用できないため、
        // onAppear で初期化するか、外部から注入する必要があります。
        // ここでは仮の実装として、後で適切に初期化します。
        // FIXME: This creates a separate ModelContainer. Should be injected.
        _syncService = StateObject(wrappedValue: CalendarSyncService(
            apiClient: GoogleCalendarClient(),
            authService: .shared,
            errorHandler: .shared,
            modelContext: ModelContext(try! ModelContainer(for: ScheduleEntry.self))
        ))
    }

    // MARK: - Computed Properties

    /// フィルタリングされたエントリー
    private var filteredEntries: [ScheduleEntry] {
        if searchText.isEmpty {
            return allEntries
        } else {
            return allEntries.filter { entry in
                entry.title.localizedCaseInsensitiveContains(searchText) ||
                (entry.body?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
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
            ZStack(alignment: .bottomTrailing) {
                // タイムラインリスト
                timelineList

                // FAB ボタン
                fabButton
            }
            .navigationTitle("タイムライン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .searchable(
                text: $searchText,
                isPresented: $showSearchBar,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "タイトル、本文、タグで検索"
            )
            .sheet(isPresented: $showNewEntrySheet) {
                JournalEditorView()
                    .environmentObject(syncService)
                    // auth is automatically inherited if this view is in the hierarchy
            }
            .onAppear {
                // 今日の日付を更新
                today = Date()

                // 同期実行
                Task {
                    do {
                        try await syncService.performFullSync()
                    } catch {
                        print("Sync failed: \(error)")
                    }
                }
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
                            TimelineRowView(entry: entry)
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
                // 初回表示時に今日のセクションにスクロール
                scrollToToday(proxy: proxy)
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
        // 検索ボタン & 設定ボタン
        ToolbarItem(placement: .navigationBarLeading) {
            HStack {
                NavigationLink(destination: SettingsView().environmentObject(syncService)) {
                    Image(systemName: "gearshape")
                }
                
                Button {
                    showSearchBar.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }

        // 今日へフォーカスボタン
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                // TODO: 今日のセクションにスクロール
            } label: {
                Image(systemName: "calendar.circle")
            }
        }

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
    private func scrollToToday(proxy: ScrollViewProxy) {
        guard let todaySection = groupedEntries.first(where: { isTodaySection($0.date) }) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                proxy.scrollTo(todaySection.date, anchor: .top)
            }
        }
    }
}