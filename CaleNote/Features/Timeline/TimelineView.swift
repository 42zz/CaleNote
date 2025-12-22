import SwiftData
import SwiftUI

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService

    @Query(sort: \CachedCalendarEvent.start, order: .reverse)
    private var cachedCalendarEvents: [CachedCalendarEvent]

    @Query(sort: \ArchivedCalendarEvent.start, order: .reverse)
    private var archivedCalendarEvents: [ArchivedCalendarEvent]

    @Query private var cachedCalendars: [CachedCalendar]

    @Query(sort: \JournalEntry.eventDate, order: .reverse)
    private var entries: [JournalEntry]

    @State private var isPresentingEditor = false
    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil

    // 同期・反映・削除の表示
    @State private var lastApplyMessage: String?
    @State private var deleteErrorMessage: String?

    // 手動同期用
    @State private var isSyncing: Bool = false
    @State private var lastSyncAt: Date?
    @State private var syncStatusMessage: String?
    @State private var syncErrorMessage: String?

    // Services（このView内で使えるように用意）
    private let syncService = CalendarSyncService()
    private let calendarToJournal = CalendarToJournalSyncService()
    private let journalSync = JournalCalendarSyncService()

    // 最近使ったタグ（上位）
    private var recentTagStats: [TagStat] {
        let stats = buildTagStats(from: entries)

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

    private var groupedItems: [(day: Date, items: [TimelineItem])] {
        let calendar = Calendar.current
        let items = timelineItems

        let groups: [Date: [TimelineItem]] = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }

        var result: [(day: Date, items: [TimelineItem])] = []
        result.reserveCapacity(groups.count)

        for (day, list) in groups {
            let sortedList = list.sorted { $0.date > $1.date }
            result.append((day: day, items: sortedList))
        }

        result.sort { $0.day > $1.day }
        return result
    }

    private func buildTagStats(from entries: [JournalEntry]) -> [TagStat] {
        var dict: [String: TagStat] = [:]

        for e in entries {
            let tags = TagExtractor.extract(from: e.body)
            for tag in tags {
                if var stat = dict[tag] {
                    stat.count += 1
                    if e.eventDate > stat.lastUsedAt {
                        stat.lastUsedAt = e.eventDate
                    }
                    dict[tag] = stat
                } else {
                    dict[tag] = TagStat(
                        id: tag,
                        tag: tag,
                        count: 1,
                        lastUsedAt: e.eventDate
                    )
                }
            }
        }

        return Array(dict.values)
    }

    private func journalItems(from entries: [JournalEntry]) -> [TimelineItem] {
        entries.map { entry in
            TimelineItem(
                id: "journal-\(entry.id.uuidString)",
                kind: .journal,
                title: entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）",
                body: entry.body,
                date: entry.eventDate,
                sourceId: entry.id.uuidString
            )
        }
    }

    private func calendarItems(from cached: [CachedCalendarEvent]) -> [TimelineItem] {
        cached.map { e in
            TimelineItem(
                id: "calendar-\(e.uid)",
                kind: .calendar,
                title: e.title,
                body: e.desc,
                date: e.start,
                sourceId: e.uid
            )
        }
    }

    private func archivedItems(from archived: [ArchivedCalendarEvent]) -> [TimelineItem] {
        archived.map { e in
            TimelineItem(
                id: "archived-\(e.uid)",
                kind: .calendar,
                title: e.title,
                body: e.desc,
                date: e.start,
                sourceId: e.uid
            )
        }
    }

    private var timelineItems: [TimelineItem] {
        // 1) 表示対象のジャーナル（検索・タグフィルタ後）
        let visibleJournals: [JournalEntry] = filteredEntries
        let journalItemsLocal: [TimelineItem] = journalItems(from: visibleJournals)

        // 2) 重複排除用の「全ジャーナルID集合」（フィルタに影響されないよう全件）
        let allJournalIdSet: Set<String> = Set(entries.map { $0.id.uuidString })

        // 3) 有効カレンダーID集合
        let enabledCalendarIds: Set<String> = Set(
            cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId })

        // 4) 有効カレンダーのイベント
        let enabledCalendarEvents: [CachedCalendarEvent] = cachedCalendarEvents.filter { ev in
            enabledCalendarIds.contains(ev.calendarId)
        }

        // 5) ジャーナルに紐づくイベントはカレンダー側で表示しない（重複排除）
        let dedupedCalendarEvents: [CachedCalendarEvent] = enabledCalendarEvents.filter { ev in
            guard let jid = ev.linkedJournalId else { return true }
            return !allJournalIdSet.contains(jid)
        }

        // 6) カレンダーイベントにも検索フィルタを適用
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredCalendarEvents: [CachedCalendarEvent] = dedupedCalendarEvents.filter { event in
            if query.isEmpty { return true }
            return event.title.localizedCaseInsensitiveContains(query)
                || (event.desc?.localizedCaseInsensitiveContains(query) ?? false)
        }

        // 7) 長期キャッシュ（ArchivedCalendarEvent）の処理
        // 有効カレンダーのアーカイブイベントを取得
        let enabledArchivedEvents: [ArchivedCalendarEvent] = archivedCalendarEvents.filter { ev in
            enabledCalendarIds.contains(ev.calendarId)
        }

        // ジャーナルに紐づくイベントは除外
        let dedupedArchivedEvents: [ArchivedCalendarEvent] = enabledArchivedEvents.filter { ev in
            guard let jid = ev.linkedJournalId else { return true }
            return !allJournalIdSet.contains(jid)
        }

        // CachedCalendarEventと重複する場合はCachedCalendarEventを優先（重複排除）
        let cachedUidSet: Set<String> = Set(filteredCalendarEvents.map { $0.uid })
        let uniqueArchivedEvents: [ArchivedCalendarEvent] = dedupedArchivedEvents.filter { ev in
            !cachedUidSet.contains(ev.uid)
        }

        // アーカイブイベントにも検索フィルタを適用
        let filteredArchivedEvents: [ArchivedCalendarEvent] = uniqueArchivedEvents.filter { event in
            if query.isEmpty { return true }
            return event.title.localizedCaseInsensitiveContains(query)
                || (event.desc?.localizedCaseInsensitiveContains(query) ?? false)
        }

        // 8) 変換
        let calendarItemsLocal: [TimelineItem] = calendarItems(from: filteredCalendarEvents)
        let archivedItemsLocal: [TimelineItem] = archivedItems(from: filteredArchivedEvents)

        // 9) 合成
        var merged: [TimelineItem] = []
        merged.reserveCapacity(journalItemsLocal.count + calendarItemsLocal.count + archivedItemsLocal.count)
        merged.append(contentsOf: journalItemsLocal)
        merged.append(contentsOf: calendarItemsLocal)
        merged.append(contentsOf: archivedItemsLocal)

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

                deleteErrorMessage = nil
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteCalendarEvent(_ event: CachedCalendarEvent) {
        Task {
            do {
                // アクセストークンを取得
                let token = try await auth.validAccessToken()

                // リモート削除（Google Calendar API）
                try await GoogleCalendarClient.deleteEvent(
                    accessToken: token,
                    calendarId: event.calendarId,
                    eventId: event.eventId
                )

                // 紐付いているジャーナルがあれば、そちらのlinkedEventIdをクリア
                if let journalId = event.linkedJournalId,
                   let linkedEntry = entries.first(where: { $0.id.uuidString == journalId }) {
                    linkedEntry.linkedEventId = nil
                    linkedEntry.linkedCalendarId = nil
                }

                // ローカルキャッシュから削除
                modelContext.delete(event)
                try modelContext.save()

                deleteErrorMessage = nil
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // 同期状態
                if isSyncing {
                    Section {
                        Text(syncStatusMessage ?? "同期中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let status = syncStatusMessage {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastSyncAt {
                    Section {
                        Text("最終同期: \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let msg = syncErrorMessage {
                    Section {
                        Text("同期エラー: \(msg)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let msg = deleteErrorMessage {
                    Section {
                        Text("削除エラー: \(msg)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let summary = filterSummaryText {
                    Section {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }

                if let msg = lastApplyMessage {
                    Section {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // タグクラウド
                if !recentTagStats.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                TagChipView(text: "すべて", isSelected: selectedTag == nil) {
                                    selectedTag = nil
                                }

                                ForEach(recentTagStats) { stat in
                                    let tag = stat.tag
                                    TagChipView(text: "#\(tag)", isSelected: selectedTag == tag) {
                                        selectedTag = (selectedTag == tag) ? nil : tag
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("最近のタグ")
                    }
                }

                // 本体
                if timelineItems.isEmpty {
                    if searchText.isEmpty && selectedTag == nil {
                        ContentUnavailableView("まだ何もありません", systemImage: "square.and.pencil")
                    } else {
                        ContentUnavailableView("見つかりませんでした", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(groupedItems, id: \.day) { section in
                        let headerTitle: String = section.day.formatted(
                            date: .abbreviated, time: .omitted)

                        Section(headerTitle) {
                            ForEach(section.items) { item in
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
                                    return archivedCalendarEvents.first(where: {
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
                                        CalendarEventDetailView(event: calendarEvent, calendar: calendar)
                                    } else if let archivedEvent {
                                        // アーカイブイベントの詳細表示（簡易版）
                                        ArchivedCalendarEventDetailView(event: archivedEvent, calendar: calendar)
                                    } else {
                                        Text("詳細を表示できません")
                                    }
                                } label: {
                                    TimelineRowView(
                                        item: item,
                                        journalEntry: entry,
                                        onDeleteJournal: nil
                                    )
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
                    }
                }
            }
            .navigationTitle("ジャーナル")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "検索"
            )
            .toolbar {
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
            .task {
                // 起動時同期（runSyncに統一）
                await runSync(isManual: false)
            }
            .refreshable {
                // pull-to-refresh
                await runSync(isManual: true)
            }
        }
    }

    @MainActor
    private func runSync(isManual: Bool) async {
        if isSyncing { return }
        isSyncing = true
        defer { isSyncing = false }

        let now = Date()
        if !SyncRateLimiter.canSync(now: now) {
            let remain = SyncRateLimiter.remainingSeconds(now: now)
            syncStatusMessage = "同期は少し待ってください（あと \(remain) 秒）"
            return
        }

        SyncRateLimiter.markSynced(at: Date())
        lastSyncAt = Date()

        syncErrorMessage = nil
        syncStatusMessage = isManual ? "手動同期中…" : "同期中…"

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
            let removed = try cleaner.cleanupEventsOutsideWindow(modelContext: modelContext, timeMin: timeMin, timeMax: timeMax)

            syncStatusMessage =
                "同期完了（更新\(apply.updatedCount) / 削除\(apply.unlinkedCount) / スキップ\(apply.skippedCount) / 競合\(apply.conflictCount) / 掃除\(removed)）"
        } catch {
            syncErrorMessage = error.localizedDescription
            syncStatusMessage = nil
        }
    }
}
