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

    @State private var syncErrorMessage: String?
    private let syncService = CalendarSyncService()

    private let calendarToJournal = CalendarToJournalSyncService()
    @State private var lastApplyMessage: String?

    private let journalSync = JournalCalendarSyncService()
    @State private var deleteErrorMessage: String?

    // ← 追加：ローカルキャッシュから作る「最近使ったタグ（上位）」。
    // とりあえず頻度順。必要なら「直近30日」などに絞れる
    private var recentTagStats: [TagStat] {
        let stats = buildTagStats(from: entries)

        // スコア: 最終使用が新しいほど優先、同じなら頻度が多いほど優先
        // 逆でもいいけど、“最近”を強くしたいので lastUsedAt を主にする
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

        // 先に判定関数に逃がすとコンパイラが楽できる
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

        // 表示は「検索：」に一本化する
        // - タグだけ → "検索：#tag"
        // - テキストだけ → "検索：keyword"
        // - 両方 → "検索：#tag keyword"
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
                    // 最終使用日時は eventDate を採用（updatedAt でもいい）
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

    private func deleteEntry(_ entry: JournalEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
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

    private var timelineItems: [TimelineItem] {
        // 1) ジャーナル
        let journalEntries: [JournalEntry] = filteredEntries
        let journalItemsLocal: [TimelineItem] = journalItems(from: journalEntries)

        // 2) ジャーナルID集合（重複除外用）
        let journalIdSet: Set<String> = Set(journalEntries.map { $0.id.uuidString })

        // 3) 有効カレンダーID集合
        let enabledCalendarIds: Set<String> = Set(
            cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId })

        // 4) 表示対象のカレンダーイベント（有効カレンダーのみ）
        let enabledCalendarEvents: [CachedCalendarEvent] = cachedCalendarEvents.filter { ev in
            enabledCalendarIds.contains(ev.calendarId)
        }

        // 5) 重複除外（linkedJournalIdがローカルに存在するならカレンダー側は表示しない）
        let dedupedCalendarEvents: [CachedCalendarEvent] = enabledCalendarEvents.filter { ev in
            guard let jid = ev.linkedJournalId else { return true }
            return !journalIdSet.contains(jid)
        }

        // 6) カレンダーイベント→TimelineItem
        let calendarItemsLocal: [TimelineItem] = calendarItems(from: dedupedCalendarEvents)

        // 7) 合成してソート
        var merged: [TimelineItem] = []
        merged.reserveCapacity(journalItemsLocal.count + calendarItemsLocal.count)
        merged.append(contentsOf: journalItemsLocal)
        merged.append(contentsOf: calendarItemsLocal)

        merged.sort { $0.date > $1.date }
        return merged
    }

    private func deleteJournalEntry(_ entry: JournalEntry) {
        Task {
            do {
                // 先にリモート削除（成功でも失敗でも、ローカルだけ消すかは好み）
                try await journalSync.deleteRemoteIfLinked(
                    entry: entry, auth: auth, modelContext: modelContext)

                // ローカルのJournal自体を消す
                modelContext.delete(entry)
                try modelContext.save()

                deleteErrorMessage = nil
            } catch {
                // ここは方針が分かれる
                // 「ローカルだけ消してneedsCalendarSync的に後で整理」でもいいし
                // 「失敗したら消さない」でもいい
                deleteErrorMessage = error.localizedDescription
            }
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

    var body: some View {
        NavigationStack {
            List {
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

                if let msg = syncErrorMessage {
                    Section {
                        Text("同期エラー: \(msg)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // タグクラウド（検索中でも出してOKだが、邪魔なら条件で隠せる）
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

                if timelineItems.isEmpty {
                    if searchText.isEmpty && selectedTag == nil {
                        ContentUnavailableView("まだ何もありません", systemImage: "square.and.pencil")
                    } else {
                        ContentUnavailableView("見つかりませんでした", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(groupedItems, id: \.day) { section in
                        Section(section.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(section.items) { item in
                                let entry: JournalEntry? = {
                                    if item.kind != .journal { return nil }
                                    return entries.first(where: {
                                        $0.id.uuidString == item.sourceId
                                    })
                                }()

                                NavigationLink {
                                    if let entry {
                                        JournalDetailView(entry: entry)
                                    } else {
                                        Text("詳細を表示できません")
                                    }
                                } label: {
                                    TimelineRowView(
                                        item: item,
                                        journalEntry: entry,
                                        onDeleteJournal: entry.map { e in
                                            { deleteJournalEntry(e) }
                                        }
                                    )
                                }
                            }

                        }
                    }
                }

            }
            .navigationTitle("ジャーナル")
            .searchable(
                text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "検索"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                JournalEditorView()
            }
            .task {
                let now = Date()
                let timeMin = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
                let timeMax = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now

                do {
                    try await syncService.syncEnabledCalendars(
                        auth: auth,
                        modelContext: modelContext,
                        calendars: cachedCalendars,
                        initialTimeMin: timeMin,
                        initialTimeMax: timeMax
                    )
                    let apply = try calendarToJournal.applyFromCachedEvents(
                        modelContext: modelContext)
                    lastApplyMessage =
                        "反映: 更新\(apply.updatedCount) / 解除\(apply.unlinkedCount) / スキップ\(apply.skippedCount)"

                    syncErrorMessage = nil
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
