import SwiftData
import SwiftUI

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JournalEntry.eventDate, order: .reverse)
    private var entries: [JournalEntry]

    @State private var isPresentingEditor = false
    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil  // ← 追加

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

    private var groupedEntries: [(day: Date, items: [JournalEntry])] {
        let calendar = Calendar.current

        // eventDate の「その日の0:00」に丸めて日付キーにする
        let groups = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.eventDate)
        }

        // 日付降順に並べて、各日の中は eventDate 降順に並べる
        return
            groups
            .map { (day: $0.key, items: $0.value.sorted { $0.eventDate > $1.eventDate }) }
            .sorted { $0.day > $1.day }
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

    var body: some View {
        NavigationStack {
            List {
                if let summary = filterSummaryText {
                    Section {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
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

                if filteredEntries.isEmpty {
                    if searchText.isEmpty && selectedTag == nil {
                        ContentUnavailableView("まだ何もありません", systemImage: "square.and.pencil")
                    } else {
                        ContentUnavailableView("見つかりませんでした", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(groupedEntries, id: \.day) { section in
                        Section(section.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(section.items) { entry in
                                NavigationLink {
                                    JournalDetailView(entry: entry)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(
                                            entry.title?.isEmpty == false
                                                ? entry.title! : "（タイトルなし）"
                                        )
                                        .font(.headline)

                                        Text(entry.body)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)

                                        // “日”でまとまっているので、ここは時刻だけの方が自然
                                        Text(entry.eventDate, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
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
        }
    }
}
