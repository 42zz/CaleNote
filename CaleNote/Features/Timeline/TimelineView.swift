import SwiftData
import SwiftUI

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService

    @Query(sort: \CachedCalendarEvent.start, order: .reverse)
    private var cachedCalendarEvents: [CachedCalendarEvent]

    @Query private var cachedCalendars: [CachedCalendar]

    @Query(sort: \JournalEntry.eventDate, order: .reverse)
    private var entries: [JournalEntry]

    @State private var isPresentingEditor = false
    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil
    @State private var isSearchPresented: Bool = false  // 検索バーの表示状態

    // 初期フォーカス管理
    @State private var hasAutoFocusedToday: Bool = false
    @State private var selectedDayKey: String? = nil  // 日付ジャンプ用（将来の機能）

    // タブ選択によるスクロールトリガー
    @Binding var selectedTab: Int
    @Binding var tabTapTrigger: Int
    @Binding var isDetailViewPresented: Bool
    @State private var lastSelectedTab: Int = 0
    @State private var lastAppearTime: Date = Date()

    // Toast表示用
    @State private var toastMessage: String?
    @State private var toastType: ToastView.ToastType = .info

    // 手動同期用
    @State private var isSyncing: Bool = false
    @State private var lastSyncAt: Date?

    // スクロール用のプロキシ参照
    @State private var scrollProxy: ScrollViewProxy?

    // 過去側ページング状態管理
    @State private var pagingState = TimelinePagingState()

    // Services（このView内で使えるように用意）
    private let syncService = CalendarSyncService()
    private let calendarToJournal = CalendarToJournalSyncService()
    private let journalSync = JournalCalendarSyncService()

    // 個別再送状態
    @State private var isResendingIndividual: Bool = false
    @State private var showResendConfirmation: Bool = false
    @State private var entryToResend: JournalEntry?

    // デフォルト値（統一カードの視覚的整合性のため）
    private let defaultColorHex: String = "#3B82F6"  // ミュートブルー
    private let defaultIconName: String = "calendar"

    // 辞書化されたlookup（型推論とパフォーマンスの改善）
    private var entriesById: [String: JournalEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id.uuidString, $0) })
    }

    private var cachedEventsByUid: [String: CachedCalendarEvent] {
        Dictionary(uniqueKeysWithValues: cachedCalendarEvents.map { ($0.uid, $0) })
    }

    private var archivedEventsByUid: [String: ArchivedCalendarEvent] {
        Dictionary(uniqueKeysWithValues: pagingState.loadedArchivedEvents.map { ($0.uid, $0) })
    }

    private var calendarsById: [String: CachedCalendar] {
        Dictionary(uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })
    }

    // task id を外に出す（型推論の負荷軽減）
    private var calendarsTaskId: String {
        cachedCalendars
            .map { "\($0.calendarId):\($0.isEnabled)" }
            .joined(separator: ",")
    }

    // 最近使ったタグ（上位）
    private var recentTagStats: [TagStat] {
        // 有効なカレンダーID集合を取得
        let enabledCalendarIds: Set<String> = Set(
            cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId }
        )

        // 有効なカレンダーのイベントのみを対象
        let enabledCalendarEvents = cachedCalendarEvents.filter { event in
            enabledCalendarIds.contains(event.calendarId)
        }

        // 同期対象期間内のイベントも含めてタグ統計を構築
        let stats = buildTagStats(
            from: entries,
            cachedEvents: enabledCalendarEvents
        )

        let sorted = stats.sorted { a, b in
            if a.lastUsedAt != b.lastUsedAt { return a.lastUsedAt > b.lastUsedAt }
            if a.count != b.count { return a.count > b.count }
            return a.tag < b.tag
        }

        return Array(sorted.prefix(20))
    }

    private var filteredEntries: [JournalEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = selectedTag

        func matchesText(_ entry: JournalEntry) -> Bool {
            if query.isEmpty { return true }
            let title = entry.title ?? ""
            return title.localizedCaseInsensitiveContains(query)
                || entry.body.localizedCaseInsensitiveContains(query)
        }

        func matchesTag(_ entry: JournalEntry) -> Bool {
            guard let tag = selected else { return true }
            let tags = TagExtractor.extract(from: entry.body)
            return tags.contains(tag)
        }

        return entries.filter { entry in
            matchesText(entry) && matchesTag(entry)
        }
    }

    private var filterSummaryText: String? {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagToken = selectedTag.map { "#\($0)" } ?? ""

        let combined: String = {
            if q.isEmpty { return tagToken }
            if tagToken.isEmpty { return q }
            return "\(tagToken) \(q)"
        }()

        return combined.isEmpty ? nil : "検索：\(combined)"
    }

    /// 日付からYYYYMMDD形式のキーを生成
    private func dayKey(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        if let year = components.year, let month = components.month, let day = components.day {
            return String(format: "%04d%02d%02d", year, month, day)
        }
        return ""
    }

    /// 今日の日付キーを取得
    private var todayKey: String {
        dayKey(from: Date())
    }

    private var groupedItems: [(day: Date, items: [TimelineItem])] {
        let calendar = Calendar.current
        let items = timelineItems

        let groups: [Date: [TimelineItem]] = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }

        var result: [(day: Date, items: [TimelineItem])] = []
        result.reserveCapacity(groups.count + 1)  // 今日セクション追加の可能性を考慮

        for (day, list) in groups {
            let sortedList = list.sorted { $0.date > $1.date }
            result.append((day: day, items: sortedList))
        }

        result.sort { $0.day > $1.day }

        // 今日セクションが存在しない場合は空セクションを追加
        let today = calendar.startOfDay(for: Date())
        let hasTodaySection = result.contains { calendar.isDate($0.day, inSameDayAs: today) }
        if !hasTodaySection {
            result.append((day: today, items: []))
            // 日付順を維持するため再ソート
            result.sort { $0.day > $1.day }
        }

        return result
    }

    /// タグ統計を構築（JournalEntryと同期対象期間内のCachedCalendarEventから）
    private func buildTagStats(
        from entries: [JournalEntry],
        cachedEvents: [CachedCalendarEvent]
    ) -> [TagStat] {
        var dict: [String: TagStat] = [:]

        // 同期対象期間を取得
        let (timeMin, timeMax) = SyncSettings.windowDates()

        // JournalEntryからタグを抽出
        for entry in entries {
            let tags = TagExtractor.extract(from: entry.body)
            for tag in tags {
                if var stat = dict[tag] {
                    stat.count += 1
                    if entry.eventDate > stat.lastUsedAt {
                        stat.lastUsedAt = entry.eventDate
                    }
                    dict[tag] = stat
                } else {
                    dict[tag] = TagStat(
                        id: tag,
                        tag: tag,
                        count: 1,
                        lastUsedAt: entry.eventDate
                    )
                }
            }
        }

        // 同期対象期間内のCachedCalendarEventからタグを抽出
        // 注意: JournalEntryと紐付いているイベントは重複カウントを避けるため、
        // linkedJournalIdがnilのイベントのみを対象とする
        for event in cachedEvents {
            // 同期対象期間内かチェック
            guard event.start >= timeMin && event.start <= timeMax else {
                continue
            }

            // JournalEntryと紐付いている場合はスキップ（既にカウント済み）
            if event.linkedJournalId != nil {
                continue
            }

            // descriptionからタグを抽出
            guard let desc = event.desc, !desc.isEmpty else {
                continue
            }

            let tags = TagExtractor.extract(from: desc)
            for tag in tags {
                if var stat = dict[tag] {
                    stat.count += 1
                    if event.start > stat.lastUsedAt {
                        stat.lastUsedAt = event.start
                    }
                    dict[tag] = stat
                } else {
                    dict[tag] = TagStat(
                        id: tag,
                        tag: tag,
                        count: 1,
                        lastUsedAt: event.start
                    )
                }
            }
        }

        return Array(dict.values)
    }

    private func journalItems(from entries: [JournalEntry]) -> [TimelineItem] {
        // カレンダー辞書を作成して高速検索
        let calendarDict = Dictionary(
            uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })

        return entries.map { entry in
            // colorHexはエントリ固有、ただし空文字列やデフォルト値の場合はカレンダーの色を使用
            let colorHex: String
            if entry.colorHex.isEmpty || entry.colorHex == "#3B82F6" {
                // カレンダーの色を使用
                if let linkedCalendarId = entry.linkedCalendarId,
                    let calendar = calendarDict[linkedCalendarId],
                    !calendar.userColorHex.isEmpty
                {
                    colorHex = calendar.userColorHex
                } else {
                    colorHex = defaultColorHex
                }
            } else {
                colorHex = entry.colorHex
            }

            // linkedCalendarIdからカレンダーを取得してiconNameを決定
            let iconName: String
            if let linkedCalendarId = entry.linkedCalendarId,
                let calendar = calendarDict[linkedCalendarId]
            {
                iconName = calendar.iconName.isEmpty ? defaultIconName : calendar.iconName
            } else {
                // エントリ固有のiconNameを使用、なければデフォルト
                iconName = entry.iconName.isEmpty ? defaultIconName : entry.iconName
            }

            return TimelineItem(
                id: "journal-\(entry.id.uuidString)",
                kind: .journal,
                title: entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）",
                body: entry.body,
                date: entry.eventDate,
                sourceId: entry.id.uuidString,
                colorHex: colorHex,
                iconName: iconName,
                isAllDay: false  // ジャーナルは終日ではない
            )
        }
    }

    private func calendarItems(from cached: [CachedCalendarEvent]) -> [TimelineItem] {
        // カレンダー辞書を作成して高速検索
        let calendarDict = Dictionary(
            uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })

        return cached.map { e in
            // CachedCalendarのcolorHex/iconNameを確実に反映
            let calendar = calendarDict[e.calendarId]
            let colorHex: String
            if let cal = calendar, !cal.userColorHex.isEmpty {
                colorHex = cal.userColorHex
            } else {
                colorHex = defaultColorHex
            }

            let iconName: String
            if let cal = calendar, !cal.iconName.isEmpty {
                iconName = cal.iconName
            } else {
                iconName = defaultIconName
            }

            return TimelineItem(
                id: "calendar-\(e.uid)",
                kind: .calendar,
                title: e.title,
                body: e.desc,
                date: e.start,
                sourceId: e.uid,
                colorHex: colorHex,
                iconName: iconName,
                isAllDay: e.isAllDay
            )
        }
    }

    private func archivedItems(from archived: [ArchivedCalendarEvent]) -> [TimelineItem] {
        // カレンダー辞書を作成して高速検索
        let calendarDict = Dictionary(
            uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })

        return archived.map { e in
            // CachedCalendarのcolorHex/iconNameを確実に反映
            let calendar = calendarDict[e.calendarId]
            let colorHex: String
            if let cal = calendar, !cal.userColorHex.isEmpty {
                colorHex = cal.userColorHex
            } else {
                colorHex = defaultColorHex
            }

            let iconName: String
            if let cal = calendar, !cal.iconName.isEmpty {
                iconName = cal.iconName
            } else {
                iconName = defaultIconName
            }

            return TimelineItem(
                id: "archived-\(e.uid)",
                kind: .calendar,
                title: e.title,
                body: e.desc,
                date: e.start,
                sourceId: e.uid,
                colorHex: colorHex,
                iconName: iconName,
                isAllDay: e.isAllDay
            )
        }
    }

    private var timelineItems: [TimelineItem] {
        // 1) 表示対象のジャーナル（検索・タグフィルタ後）
        let visibleJournals: [JournalEntry] = filteredEntries
        let journalItemsLocal: [TimelineItem] = journalItems(from: visibleJournals)

        // 2) 重複排除用の「全ジャーナルID集合」（フィルタに影響されないよう全件）
        let allJournalIdSet: Set<String> = Set(entries.map { $0.id.uuidString })

        // 2-1) 表示対象のジャーナルID集合（重複排除に使用）
        let visibleJournalIdSet: Set<String> = Set(visibleJournals.map { $0.id.uuidString })

        // 2-2) 表示対象のジャーナルに対応するカレンダーイベントのUID集合（重複排除に使用）
        // linkedEventIdとlinkedCalendarIdを使って、ジャーナルエントリに対応するカレンダーイベントを特定
        let journalLinkedEventUids: Set<String> = Set(
            visibleJournals.compactMap { entry in
                guard let calendarId = entry.linkedCalendarId,
                    let eventId = entry.linkedEventId
                else { return nil }
                return "\(calendarId):\(eventId)"
            })

        // 3) 有効カレンダーID集合
        let enabledCalendarIds: Set<String> = Set(
            cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId })

        // 4) 有効カレンダーのイベント
        let enabledCalendarEvents: [CachedCalendarEvent] = cachedCalendarEvents.filter { ev in
            enabledCalendarIds.contains(ev.calendarId)
        }

        // 5) ジャーナルに紐づくイベントはカレンダー側で表示しない（重複排除）
        // 方法1: linkedJournalIdでチェック
        // 方法2: linkedEventIdとlinkedCalendarIdでチェック（より確実）
        let dedupedCalendarEvents: [CachedCalendarEvent] = enabledCalendarEvents.filter { ev in
            // linkedJournalIdでチェック
            if let jid = ev.linkedJournalId {
                if allJournalIdSet.contains(jid) || visibleJournalIdSet.contains(jid) {
                    return false
                }
            }

            // linkedEventIdとlinkedCalendarIdでチェック（より確実）
            if journalLinkedEventUids.contains(ev.uid) {
                return false
            }

            return true
        }

        // 6) カレンダーイベントにも検索フィルタとタグフィルタを適用
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredCalendarEvents: [CachedCalendarEvent] = dedupedCalendarEvents.filter { event in
            // テキスト検索
            let matchesText: Bool = {
                if query.isEmpty { return true }
                return event.title.localizedCaseInsensitiveContains(query)
                    || (event.desc?.localizedCaseInsensitiveContains(query) ?? false)
            }()

            // タグ検索
            let matchesTag: Bool = {
                guard let tag = selectedTag else { return true }
                guard let desc = event.desc, !desc.isEmpty else { return false }
                let tags = TagExtractor.extract(from: desc)
                return tags.contains(tag)
            }()

            return matchesText && matchesTag
        }

        // 7) 長期キャッシュ（ArchivedCalendarEvent）の処理
        // 過去側ページングで取得した長期キャッシュを含める
        let archivedEvents = pagingState.loadedArchivedEvents.filter { ev in
            enabledCalendarIds.contains(ev.calendarId)
        }

        // ジャーナルに紐づくイベントは除外
        let dedupedArchivedEvents = archivedEvents.filter { ev in
            if let jid = ev.linkedJournalId {
                if allJournalIdSet.contains(jid) || visibleJournalIdSet.contains(jid) {
                    return false
                }
            }
            if journalLinkedEventUids.contains(ev.uid) {
                return false
            }
            return true
        }

        // 短期キャッシュと重複する場合は短期を優先（uid で排除）
        let cachedUidSet = Set(filteredCalendarEvents.map { $0.uid })
        let uniqueArchivedEvents = dedupedArchivedEvents.filter { !cachedUidSet.contains($0.uid) }

        // アーカイブイベントにも検索フィルタとタグフィルタを適用
        let filteredArchivedEvents = uniqueArchivedEvents.filter { event in
            let matchesText: Bool = {
                if query.isEmpty { return true }
                return event.title.localizedCaseInsensitiveContains(query)
                    || (event.desc?.localizedCaseInsensitiveContains(query) ?? false)
            }()

            let matchesTag: Bool = {
                guard let tag = selectedTag else { return true }
                guard let desc = event.desc, !desc.isEmpty else { return false }
                let tags = TagExtractor.extract(from: desc)
                return tags.contains(tag)
            }()

            return matchesText && matchesTag
        }

        // 8) 変換
        let calendarItemsLocal: [TimelineItem] = calendarItems(from: filteredCalendarEvents)
        let archivedItemsLocal: [TimelineItem] = archivedItems(from: filteredArchivedEvents)

        // 9) 合成
        // 2段階データソース：短期キャッシュ + JournalEntry + 長期キャッシュ（uid重複排除済み）
        var merged: [TimelineItem] = []
        merged.reserveCapacity(
            journalItemsLocal.count + calendarItemsLocal.count + archivedItemsLocal.count
        )
        merged.append(contentsOf: journalItemsLocal)
        merged.append(contentsOf: calendarItemsLocal)
        merged.append(contentsOf: archivedItemsLocal)

        // ソート（降順、日時で安定化）
        merged.sort { $0.date > $1.date }
        return merged
    }

    private func deleteJournalEntry(_ entry: JournalEntry) {
        Task {
            do {
                // リモート削除（紐付いている場合のみ）
                try await journalSync.deleteRemoteIfLinked(
                    entry: entry, auth: auth, modelContext: modelContext)

                // ローカル削除
                modelContext.delete(entry)
                try modelContext.save()

                toastMessage = "ジャーナルを削除しました"
                toastType = ToastView.ToastType.success
            } catch {
                toastMessage = "削除エラー: \(error.localizedDescription)"
                toastType = ToastView.ToastType.error
            }
        }
    }

    private func deleteCalendarEvent(_ event: CachedCalendarEvent) {
        Task {
            do {
                // アクセストークンを取得
                let token = try await auth.validAccessToken()

                // リモート削除（Google Calendar API）
                _ = try await GoogleCalendarClient.deleteEvent(
                    accessToken: token,
                    calendarId: event.calendarId,
                    eventId: event.eventId
                )

                // 紐付いているジャーナルがあれば、そちらのlinkedEventIdをクリア
                if let journalId = event.linkedJournalId,
                    let linkedEntry = entries.first(where: { $0.id.uuidString == journalId })
                {
                    linkedEntry.linkedEventId = nil
                    linkedEntry.linkedCalendarId = nil
                }

                // ローカルキャッシュから削除
                modelContext.delete(event)
                try modelContext.save()

                toastMessage = "イベントを削除しました"
                toastType = ToastView.ToastType.success
            } catch {
                toastMessage = "削除エラー: \(error.localizedDescription)"
                toastType = ToastView.ToastType.error
            }
        }
    }

    private func handleSyncBadgeTap(for entry: JournalEntry) {
        if entry.hasConflict {
            // 競合の場合は詳細画面に遷移してもらう（ここでは何もしない）
            // NavigationLinkが自動的に遷移する
            return
        } else if entry.needsCalendarSync {
            // 同期失敗の場合は確認ダイアログを表示
            entryToResend = entry
            showResendConfirmation = true
        }
    }

    private func resendIndividualEntry() {
        guard let entry = entryToResend else { return }

        Task {
            isResendingIndividual = true

            do {
                let targetCalendarId =
                    entry.linkedCalendarId ?? JournalWriteSettings.loadWriteCalendarId()
                    ?? "primary"

                try await journalSync.syncOne(
                    entry: entry,
                    targetCalendarId: targetCalendarId,
                    auth: auth,
                    modelContext: modelContext
                )

                toastMessage = "再送成功"
                toastType = ToastView.ToastType.success
            } catch {
                toastMessage = "再送エラー: \(error.localizedDescription)"
                toastType = ToastView.ToastType.error
            }

            isResendingIndividual = false
            entryToResend = nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    timelineListContent()
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .safeAreaInset(edge: .bottom) {
                    // タブバーの高さ分のスペースを確保
                    Color.clear.frame(height: 60)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "検索"
                )
                .toolbar {
                    timelineToolbar()
                }
                .sheet(isPresented: $isPresentingEditor) {
                    JournalEditorView()
                }
                .alert("再送しますか？", isPresented: $showResendConfirmation) {
                    Button("キャンセル", role: .cancel) {
                        entryToResend = nil
                    }
                    Button("再送") {
                        resendIndividualEntry()
                    }
                } message: {
                    if let entry = entryToResend {
                        Text("「\(entry.title ?? "無題")」をカレンダーに再送します。")
                    } else {
                        Text("ジャーナルをカレンダーに再送します。")
                    }
                }
                .task(id: calendarsTaskId) {
                    await onCalendarsChanged()
                }
                .refreshable {
                    await runSync(isManual: true)
                }
                .onAppear {
                    // スクロールプロキシを保存
                    scrollProxy = proxy

                    // 初期フォーカス処理
                    handleInitialFocus(proxy: proxy)
                }
                .onChange(of: selectedDayKey) { _, newValue in
                    scrollToSelectedDay(proxy: proxy, newKey: newValue)
                }
                .onChange(of: selectedTab) { oldValue, newValue in
                    print("🔄 タブ変更: \(oldValue) → \(newValue), 現在のタブ: \(selectedTab)")
                    // タブ選択状態を記録するのみ（スクロールはonChangeで同じタブ再タップ時のみ）
                    lastSelectedTab = newValue
                }
                .onChange(of: tabTapTrigger) { _, newValue in
                    print("🔔 タブタップトリガー検知: \(newValue)")
                    // 検索中でない場合のみスクロール
                    let isSearching =
                        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedTag != nil
                    if !isSearching {
                        scrollToToday(proxy: proxy)
                    } else {
                        print("⚠️ 検索中のためスクロールをスキップ")
                    }
                }
                .toast(message: $toastMessage, type: $toastType, duration: 4.0)
            }
        }
    }

    // MARK: - ViewBuilder Functions

    @ViewBuilder
    private func timelineListContent() -> some View {
        // 最上部アンカー（スクロール用）
        // Color.clear
        //     .frame(height: 0)
        //     .listRowInsets(EdgeInsets())
        //     .listRowBackground(Color.clear)
        //     .listRowSeparator(.hidden)
        //     .id("timeline-top")

        if let summary = filterSummaryText {
            Section {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }

        let items = timelineItems
        let isEmpty = items.isEmpty
        let hasNoSearch = searchText.isEmpty && selectedTag == nil

        if isEmpty {
            if hasNoSearch {
                ContentUnavailableView("まだ何もありません", systemImage: "square.and.pencil")
            } else {
                ContentUnavailableView("見つかりませんでした", systemImage: "magnifyingglass")
            }
        } else {
            let grouped = groupedItems
            ForEach(grouped.indices, id: \.self) { index in
                timelineSection(grouped: grouped, index: index)
            }

            // 過去側センチネル行（過去側ページングのトリガー）
            pastSentinelRow()
        }
    }

    @ViewBuilder
    private func timelineSection(grouped: [(day: Date, items: [TimelineItem])], index: Int)
        -> some View
    {
        let section = grouped[index]
        let headerTitle = section.day.formatted(date: .abbreviated, time: .omitted)
        let sectionDayKey = dayKey(from: section.day)
        let isFirstSection = index == grouped.startIndex
        let isLastSection = index == grouped.index(before: grouped.endIndex)

        Section {
            if section.items.isEmpty {
                Text("記録がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                timelineRows(
                    items: section.items,
                    isFirstSection: isFirstSection,
                    isLastSection: isLastSection
                )
            }
        } header: {
            Text(headerTitle)
        }
        .id(sectionDayKey)
    }

    @ViewBuilder
    private func timelineRows(
        items: [TimelineItem],
        isFirstSection: Bool,
        isLastSection: Bool
    ) -> some View {
        ForEach(items.indices, id: \.self) { itemIndex in
            let item = items[itemIndex]

            // 辞書参照でlookup（型推論とパフォーマンスの改善）
            let entry: JournalEntry? =
                item.kind == .journal ? entriesById[item.sourceId] : nil

            let calendarEvent: CachedCalendarEvent? =
                (item.kind == .calendar && !item.id.hasPrefix("archived-"))
                    ? cachedEventsByUid[item.sourceId] : nil

            let archivedEvent: ArchivedCalendarEvent? =
                (item.kind == .calendar && item.id.hasPrefix("archived-"))
                    ? archivedEventsByUid[item.sourceId] : nil

            let calendar: CachedCalendar? = {
                if let ce = calendarEvent { return calendarsById[ce.calendarId] }
                if let ae = archivedEvent { return calendarsById[ae.calendarId] }
                return nil
            }()

            TimelineRowLink(
                item: item,
                entry: entry,
                calendarEvent: calendarEvent,
                archivedEvent: archivedEvent,
                calendar: calendar,
                isResendingIndividual: isResendingIndividual,
                resendingEntryId: entryToResend?.id.uuidString,
                isFirstItemInFirstSection: false,  // 使用しない
                isLastItemInLastSection: false,  // 使用しない
                onSyncBadgeTap: entry != nil ? { handleSyncBadgeTap(for: entry!) } : nil,
                onDeleteJournal: { deleteJournalEntry($0) },
                onDeleteCalendar: { deleteCalendarEvent($0) },
                isDetailViewPresented: $isDetailViewPresented
            )
            // ページネーショントリガーは削除
            // 短期キャッシュは同期範囲内のデータが全て取得済みのため、ページネーション不要
        }
    }

    // 過去側センチネル行（過去側ページングのトリガー）
    @ViewBuilder
    private func pastSentinelRow() -> some View {
        if pagingState.isLoadingPast {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 12)
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if !pagingState.hasReachedEarliestData {
            Color.clear
                .frame(height: 1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onAppear {
                    print("👁️ 過去側センチネルが表示されました")
                    loadPastPageIfNeeded()
                }
        }
    }

    @ToolbarContentBuilder
    private func timelineToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isSearchPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
        }

        ToolbarItem(placement: .principal) {
            Button {
                scrollToTop()
            } label: {
                Text("ジャーナル")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .disabled(isSyncing)
            .buttonStyle(.glassProminent)
            .tint(Color.blue)
        }
    }

    // MARK: - Event Handlers

    @MainActor
    private func onCalendarsChanged() async {
        // カレンダー設定が変更された場合は再初期化
        let enabledCalendarIds = Set(
            cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId }
        )

        // 短期キャッシュは同期範囲内のデータが全て取得済みのため、初期ロード不要
        print("🚀 タイムライン表示準備完了（カレンダー設定: \(enabledCalendarIds.count)個有効）")

        // 起動時同期（runSyncに統一）
        await runSync(isManual: false)
    }

    private func handleInitialFocus(proxy: ScrollViewProxy) {
        // 初期フォーカス: 検索中でない場合のみ実行
        let isSearching =
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedTag != nil
        if !hasAutoFocusedToday && !isSearching {
            // 日付ジャンプで選択された日がある場合はそれを優先、なければ今日
            let targetKey = selectedDayKey ?? todayKey
            // 少し遅延を入れてレイアウトが確定してからスクロール
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    proxy.scrollTo(targetKey, anchor: .top)
                }
                hasAutoFocusedToday = true
            }
        }
    }

    private func scrollToSelectedDay(proxy: ScrollViewProxy, newKey: String?) {
        // 日付ジャンプで選択された日が変更された場合、その日にスクロール
        if let newKey = newKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    proxy.scrollTo(newKey, anchor: .top)
                }
            }
        }
    }

    private func scrollToToday(proxy: ScrollViewProxy) {
        // 今日のセクションにスクロール
        let today = todayKey
        print("📅 今日にスクロール開始: \(today)")

        // レイアウトが確定するまで待つ（タブ切り替え時は特に必要）
        Task { @MainActor in
            // 少し待ってからスクロール（レイアウト確定を待つ）
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒

            // 今日のセクションが存在するか確認
            let grouped = groupedItems
            let calendar = Calendar.current
            let todayDate = calendar.startOfDay(for: Date())
            let hasTodaySection = grouped.contains {
                calendar.isDate($0.day, inSameDayAs: todayDate)
            }

            print(
                "📅 今日のセクション確認: hasTodaySection=\(hasTodaySection), grouped.count=\(grouped.count)")
            if hasTodaySection {
                print("📅 今日のセクションが見つかりました。スクロール実行: \(today)")
                // 複数回試行して確実にスクロールする
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(today, anchor: .top)
                }
                // 念のため少し待ってからもう一度試行
                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2秒
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(today, anchor: .top)
                }
            } else {
                print("⚠️ 今日のセクションが見つかりませんでした。groupedItems: \(grouped.map { dayKey(from: $0.day) })")
            }
        }
    }

    private func scrollToTop() {
        print("⬆️ 最上部にスクロール開始")
        guard let proxy = scrollProxy else {
            print("⚠️ scrollProxyが設定されていません")
            return
        }

        // 画面の最上部（もう上にスクロールできない位置）にスクロール
        // groupedItemsの最初のセクション（最も新しい日付）にスクロール
        let grouped = groupedItems
        guard let firstSection = grouped.first else {
            print("⚠️ スクロール対象のセクションがありません")
            return
        }

        let firstSectionKey = dayKey(from: firstSection.day)
        print("⬆️ 最初のセクションにスクロール: \(firstSectionKey)")
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(firstSectionKey, anchor: .top)
        }
    }

    @MainActor
    private func runSync(isManual: Bool) async {
        if isSyncing { return }
        isSyncing = true
        defer { isSyncing = false }

        // ログインしていない場合の処理
        guard auth.user != nil else {
            // 初期起動時はエラーメッセージを表示しない（正常な状態）
            if isManual {
                // 手動同期の場合は、ログインが必要であることを通知
                toastMessage = "ログインが必要です（設定からログインしてください）"
                toastType = ToastView.ToastType.info
            }
            return
        }

        let now = Date()
        if !SyncRateLimiter.canSync(now: now) {
            let remain = SyncRateLimiter.remainingSeconds(now: now)
            toastMessage = "同期は少し待ってください（あと \(remain) 秒）"
            toastType = ToastView.ToastType.warning
            return
        }

        SyncRateLimiter.markSynced(at: Date())
        lastSyncAt = Date()

        toastMessage = isManual ? "手動同期中…" : "同期中…"
        toastType = ToastView.ToastType.info

        let (timeMin, timeMax) = SyncSettings.windowDates()

        do {
            try await syncService.syncEnabledCalendars(
                auth: auth,
                modelContext: modelContext,
                calendars: cachedCalendars,
                initialTimeMin: timeMin,
                initialTimeMax: timeMax
            )

            let apply = try calendarToJournal.applyFromCachedEvents(modelContext: modelContext)
            let cleaner = CalendarCacheCleaner()
            let removed = try cleaner.cleanupEventsOutsideWindow(
                modelContext: modelContext, timeMin: timeMin, timeMax: timeMax)

            // 最終同期時間を含めたメッセージ
            let syncTime = lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "不明"
            toastMessage =
                "同期完了（更新\(apply.updatedCount) / 削除\(apply.unlinkedCount) / スキップ\(apply.skippedCount) / 競合\(apply.conflictCount) / 掃除\(removed)）\n最終同期: \(syncTime)"
            toastType = ToastView.ToastType.success
        } catch {
            // エラーメッセージから「未ログインです」を除外（初期起動時の正常な状態）
            let errorDesc = error.localizedDescription
            if errorDesc.contains("未ログインです") && !isManual {
                // 初期起動時で未ログインの場合はエラーを表示しない
                return
            }
            toastMessage = "同期エラー: \(errorDesc)"
            toastType = ToastView.ToastType.error
        }
    }

    /// 過去方向のページをロード
    /// 短期キャッシュの最古日付より古い長期キャッシュを取得
    private func loadPastPageIfNeeded() {
        let enabledCalendarIds = Set(cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId })

        // 長期キャッシュの境界が既に存在する場合は、それを使用
        let fromDayKey: Int
        if let pagingBoundary = pagingState.earliestPagingDayKey {
            // 2回目以降: 長期キャッシュの最古日付より前を取得
            fromDayKey = pagingBoundary
            print("📄 過去ページロードトリガー: 長期キャッシュ境界使用 fromDayKey=\(fromDayKey)")
        } else {
            // 初回: 短期キャッシュとジャーナルの最古日付を計算
            let enabledCachedEvents = cachedCalendarEvents.filter { enabledCalendarIds.contains($0.calendarId) }
            let cachedOldest = enabledCachedEvents.map { makeDayKeyInt(from: $0.start) }.min()
            let journalOldest = entries.map { makeDayKeyInt(from: $0.eventDate) }.min()

            // 両方の最古日付のうち、より古い方を使用
            if let cached = cachedOldest, let journal = journalOldest {
                fromDayKey = min(cached, journal)
            } else if let cached = cachedOldest {
                fromDayKey = cached
            } else if let journal = journalOldest {
                fromDayKey = journal
            } else {
                // データがない場合は今日を基準にする
                fromDayKey = makeDayKeyInt(from: Date())
            }
            print("📄 過去ページロードトリガー: 初回ロード fromDayKey=\(fromDayKey), 短期最古=\(cachedOldest ?? 0), ジャーナル最古=\(journalOldest ?? 0)")
        }

        Task {
            await pagingState.loadPastPage(
                fromDayKey: fromDayKey,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
        }
    }

    /// 日付からYYYYMMDD形式のInt型dayKeyを生成
    private func makeDayKeyInt(from date: Date) -> Int {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return year * 10000 + month * 100 + day
    }
}

