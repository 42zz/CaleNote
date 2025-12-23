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

    // ページング状態管理
    @State private var pagingState = TimelinePagingState()

    @State private var isPresentingEditor = false
    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil
    @State private var isSearchPresented: Bool = false  // 検索バーの表示状態

    // 初期フォーカス管理
    @State private var hasAutoFocusedToday: Bool = false
    @State private var selectedDayKey: String? = nil  // 日付ジャンプ用（将来の機能）
    @State private var hasInitialLoadCompleted: Bool = false

    // Toast表示用
    @State private var toastMessage: String?
    @State private var toastType: ToastView.ToastType = .info

    // 手動同期用
    @State private var isSyncing: Bool = false
    @State private var lastSyncAt: Date?

    // 最後にトリガーした方向を記録（トリム処理用）
    @State private var lastScrollDirection: TimelinePagingState.ScrollDirection = .past

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
        let calendarDict = Dictionary(uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })
        
        return entries.map { entry in
            // colorHexはエントリ固有、ただし空文字列やデフォルト値の場合はカレンダーの色を使用
            let colorHex: String
            if entry.colorHex.isEmpty || entry.colorHex == "#3B82F6" {
                // カレンダーの色を使用
                if let linkedCalendarId = entry.linkedCalendarId,
                   let calendar = calendarDict[linkedCalendarId],
                   !calendar.userColorHex.isEmpty {
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
                iconName: iconName
            )
        }
    }

    private func calendarItems(from cached: [CachedCalendarEvent]) -> [TimelineItem] {
        // カレンダー辞書を作成して高速検索
        let calendarDict = Dictionary(uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })
        
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
                iconName: iconName
            )
        }
    }

    private func archivedItems(from archived: [ArchivedCalendarEvent]) -> [TimelineItem] {
        // カレンダー辞書を作成して高速検索
        let calendarDict = Dictionary(uniqueKeysWithValues: cachedCalendars.map { ($0.calendarId, $0) })
        
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
                iconName: iconName
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
        let journalLinkedEventUids: Set<String> = Set(visibleJournals.compactMap { entry in
            guard let calendarId = entry.linkedCalendarId,
                  let eventId = entry.linkedEventId else { return nil }
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
        // ページング状態から取得し、有効なカレンダーIDでフィルタリング
        // （カレンダーの表示設定が変更された場合に備えて、ここでもフィルタリング）
        let enabledArchivedEvents: [ArchivedCalendarEvent] = pagingState.loadedArchivedEvents.filter { ev in
            enabledCalendarIds.contains(ev.calendarId)
        }

        // ジャーナルに紐づくイベントは除外
        // 全ジャーナルID集合と表示対象ジャーナルID集合の両方をチェック
        // また、linkedEventIdとlinkedCalendarIdでもチェック
        let dedupedArchivedEvents: [ArchivedCalendarEvent] = enabledArchivedEvents.filter { ev in
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

        // CachedCalendarEventと重複する場合はCachedCalendarEventを優先（重複排除）
        let cachedUidSet: Set<String> = Set(filteredCalendarEvents.map { $0.uid })
        let uniqueArchivedEvents: [ArchivedCalendarEvent] = dedupedArchivedEvents.filter { ev in
            !cachedUidSet.contains(ev.uid)
        }

        // アーカイブイベントにも検索フィルタとタグフィルタを適用
        let filteredArchivedEvents: [ArchivedCalendarEvent] = uniqueArchivedEvents.filter { event in
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

        // 8) 変換
        let calendarItemsLocal: [TimelineItem] = calendarItems(from: filteredCalendarEvents)
        let archivedItemsLocal: [TimelineItem] = archivedItems(from: filteredArchivedEvents)

        // 9) 合成
        // 各配列を結合してからソート（フィルタリング後の配列はソート順が保証されない可能性があるため）
        var merged: [TimelineItem] = []
        merged.reserveCapacity(
            journalItemsLocal.count + calendarItemsLocal.count + archivedItemsLocal.count)
        merged.append(contentsOf: journalItemsLocal)
        merged.append(contentsOf: calendarItemsLocal)
        merged.append(contentsOf: archivedItemsLocal)

        // ソート（降順）
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
                    if let summary = filterSummaryText {
                        Section {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                    }

                    // タグクラウド
                    // if !recentTagStats.isEmpty {
                    //     Section {
                    //         ScrollView(.horizontal, showsIndicators: false) {
                    //             HStack(spacing: 8) {
                    //                 TagChipView(text: "すべて", isSelected: selectedTag == nil) {
                    //                     selectedTag = nil
                    //                 }

                    //                 ForEach(recentTagStats) { stat in
                    //                     let tag = stat.tag
                    //                     TagChipView(text: "#\(tag)", isSelected: selectedTag == tag) {
                    //                         selectedTag = (selectedTag == tag) ? nil : tag
                    //                     }
                    //                 }
                    //             }
                    //             .padding(.vertical, 4)
                    //         }
                    //     } header: {
                    //         Text("最近のタグ")
                    //     }
                    // }

                    // 本体
                    if timelineItems.isEmpty {
                        if searchText.isEmpty && selectedTag == nil {
                            ContentUnavailableView("まだ何もありません", systemImage: "square.and.pencil")
                        } else {
                            ContentUnavailableView("見つかりませんでした", systemImage: "magnifyingglass")
                        }
                    } else {
                        ForEach(Array(groupedItems.enumerated()), id: \.element.day) { index, section in
                            let headerTitle: String = section.day.formatted(
                                date: .abbreviated, time: .omitted)
                            let sectionDayKey = dayKey(from: section.day)
                            let isFirstSection = index == 0
                            let isLastSection = index == groupedItems.count - 1

                            Section {
                                // 未来側番兵と読み込み中表示（最初のセクションの先頭）
                                if isFirstSection {
                                    if pagingState.isLoadingFuture {
                                        HStack {
                                            Spacer()
                                            ProgressView()
                                                .padding(.vertical, 12)
                                            Spacer()
                                        }
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .listRowBackground(Color.clear)
                                    } else {
                                        Color.clear
                                            .frame(height: 0)
                                            .listRowInsets(EdgeInsets())
                                            .listRowBackground(Color.clear)
                                            .onAppear {
                                                print("👁️ 未来側番兵が表示されました")
                                                loadFuturePageIfNeeded()
                                            }
                                    }
                                }

                                if section.items.isEmpty {
                                    // 空セクション（今日にアイテムがない場合）のプレースホルダー
                                    Text("記録がありません")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                                        let isFirstItem = itemIndex == 0
                                        let isLastItem = itemIndex == section.items.count - 1
                                        let isFirstItemInFirstSection = isFirstSection && isFirstItem
                                        let isLastItemInLastSection = isLastSection && isLastItem
                                        
                                        let entry: JournalEntry? = {
                                            if item.kind != .journal { return nil }
                                            return entries.first(where: {
                                                $0.id.uuidString == item.sourceId
                                            })
                                        }()

                                        let calendarEvent: CachedCalendarEvent? = {
                                            if item.kind != .calendar { return nil }
                                            if item.id.hasPrefix("archived-") { return nil }
                                            return cachedCalendarEvents.first(where: {
                                                $0.uid == item.sourceId
                                            })
                                        }()

                                        let archivedEvent: ArchivedCalendarEvent? = {
                                            if item.kind != .calendar { return nil }
                                            if !item.id.hasPrefix("archived-") { return nil }
                                            return pagingState.loadedArchivedEvents.first(where: {
                                                $0.uid == item.sourceId
                                            })
                                        }()

                                        let calendar: CachedCalendar? = {
                                            if let event = calendarEvent {
                                                return cachedCalendars.first(where: {
                                                    $0.calendarId == event.calendarId
                                                })
                                            } else if let event = archivedEvent {
                                                return cachedCalendars.first(where: {
                                                    $0.calendarId == event.calendarId
                                                })
                                            }
                                            return nil
                                        }()

                                        NavigationLink {
                                            if let entry {
                                                JournalDetailView(entry: entry)
                                            } else if let calendarEvent {
                                                CalendarEventDetailView(
                                                    event: calendarEvent, calendar: calendar)
                                            } else if let archivedEvent {
                                                // アーカイブイベントの詳細表示（簡易版）
                                                ArchivedCalendarEventDetailView(
                                                    event: archivedEvent, calendar: calendar)
                                            } else {
                                                Text("詳細を表示できません")
                                            }
                                        } label: {
                                            TimelineRowView(
                                                item: item,
                                                journalEntry: entry,
                                                onDeleteJournal: nil,
                                                onSyncBadgeTap: entry != nil
                                                    ? {
                                                        handleSyncBadgeTap(for: entry!)
                                                    } : nil,
                                                syncingEntryId: isResendingIndividual ? entryToResend?.id.uuidString : nil
                                            )
                                            .padding(.top, isFirstItemInFirstSection ? 8 : 0)
                                            .padding(.bottom, isLastItemInLastSection ? 8 : 0)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            if item.kind == .journal, let entry {
                                                Button(role: .destructive) {
                                                    deleteJournalEntry(entry)
                                                } label: {
                                                    Label("削除", systemImage: "trash")
                                                }
                                            } else if item.kind == .calendar, let calendarEvent {
                                                Button(role: .destructive) {
                                                    deleteCalendarEvent(calendarEvent)
                                                } label: {
                                                    Label("削除", systemImage: "trash")
                                                }
                                            }
                                            // アーカイブイベントは削除不可（読み取り専用）
                                        }
                                    }
                                }

                                // 過去側番兵と読み込み中表示（最後のセクションの末尾）
                                if isLastSection {
                                    if pagingState.isLoadingPast {
                                        HStack {
                                            Spacer()
                                            ProgressView()
                                                .padding(.vertical, 12)
                                            Spacer()
                                        }
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .listRowBackground(Color.clear)
                                    } else {
                                        Color.clear
                                            .frame(height: 0)
                                            .listRowInsets(EdgeInsets())
                                            .listRowBackground(Color.clear)
                                            .onAppear {
                                                print("👁️ 過去側番兵が表示されました")
                                                loadPastPageIfNeeded()
                                            }
                                    }
                                }
                            } header: {
                                Text(headerTitle)
                            }
                            .id(sectionDayKey)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("ジャーナル")
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "検索"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isSyncing)  // 同期中に新規作成を止めたいなら（不要なら消してOK）
                    }
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
                .task(id: cachedCalendars.map { "\($0.calendarId):\($0.isEnabled)" }.joined(separator: ",")) {
                    // カレンダー設定が変更された場合は再初期化
                    let enabledCalendarIds = Set(
                        cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId }
                    )
                    
                    // ページング状態をリセットして再初期化
                    print("🚀 タイムライン初期ロードを開始（カレンダー設定: \(enabledCalendarIds.count)個有効）")
                    pagingState.reset()
                    hasInitialLoadCompleted = false
                    
                    await pagingState.initialLoad(
                        modelContext: modelContext,
                        enabledCalendarIds: enabledCalendarIds
                    )
                    print("🚀 初期ロード完了。ロード済みイベント数: \(pagingState.loadedArchivedEvents.count)")
                    print("🚀 最も古い日付キー: \(pagingState.earliestLoadedDayKey ?? 0)")
                    print("🚀 最も新しい日付キー: \(pagingState.latestLoadedDayKey ?? 0)")
                    hasInitialLoadCompleted = true

                    // 起動時同期（runSyncに統一）
                    await runSync(isManual: false)
                }
                .refreshable {
                    // pull-to-refresh
                    await runSync(isManual: true)
                }
                .onAppear {
                    // 初期フォーカス: 検索中でない場合のみ実行
                    let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTag != nil
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
                .onChange(of: selectedDayKey) { oldValue, newValue in
                    // 日付ジャンプで選択された日が変更された場合、その日にスクロール
                    if let newKey = newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(newKey, anchor: .top)
                            }
                        }
                    }
                }
            }
            .toast(message: $toastMessage, type: $toastType, duration: 4.0)
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

    /// 過去方向のページをロード（下スクロール時）
    private func loadPastPageIfNeeded() {
        guard hasInitialLoadCompleted else {
            print("⚠️ 初期ロード未完了のため過去ページをスキップ")
            return
        }
        guard !pagingState.isLoadingPast else {
            print("⚠️ 既にロード中のため過去ページをスキップ")
            return
        }
        guard !pagingState.hasReachedEarliestData else {
            print("⚠️ 過去データの最後に到達済み")
            return
        }

        print("📄 過去方向のページロードを開始")
        // スクロール方向を記録
        lastScrollDirection = .past

        Task {
            let enabledCalendarIds = Set(
                cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId }
            )
            print("📄 有効なカレンダー数: \(enabledCalendarIds.count)")

            await pagingState.loadPastPage(
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            print("📄 過去ページロード完了。現在のイベント数: \(pagingState.loadedArchivedEvents.count)")

            // ロード完了後、最大件数を超えていればトリム
            pagingState.trimIfNeeded(scrollDirection: lastScrollDirection)
        }
    }

    /// 未来方向のページをロード（上スクロール時）
    private func loadFuturePageIfNeeded() {
        guard hasInitialLoadCompleted else {
            print("⚠️ 初期ロード未完了のため未来ページをスキップ")
            return
        }
        guard !pagingState.isLoadingFuture else {
            print("⚠️ 既にロード中のため未来ページをスキップ")
            return
        }
        guard !pagingState.hasReachedLatestData else {
            print("⚠️ 未来データの最後に到達済み")
            return
        }

        print("📅 未来方向のページロードを開始")
        // スクロール方向を記録
        lastScrollDirection = .future

        Task {
            let enabledCalendarIds = Set(
                cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId }
            )
            print("📅 有効なカレンダー数: \(enabledCalendarIds.count)")

            await pagingState.loadFuturePage(
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            print("📅 未来ページロード完了。現在のイベント数: \(pagingState.loadedArchivedEvents.count)")

            // ロード完了後、最大件数を超えていればトリム
            pagingState.trimIfNeeded(scrollDirection: lastScrollDirection)
        }
    }
}
