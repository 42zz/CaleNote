import SwiftUI
import SwiftData

struct RelatedMemoriesSection: View {
    let targetDate: Date
    @Environment(\.modelContext) private var modelContext
    @Query private var archivedEvents: [ArchivedCalendarEvent]
    @Query private var cachedCalendars: [CachedCalendar]

    @State private var relatedItems: [RelatedMemoryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let service = RelatedMemoryService()
    private let settings = RelatedMemorySettings.load()
    
    /// 有効なカレンダーID集合
    private var enabledCalendarIds: Set<String> {
        Set(cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // セクションヘッダー
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.blue)
                Text("関連するエントリー")
                    .font(.headline)

                Spacer()

                if settings.hasAnyEnabled {
                    Text(settings.enabledConditionsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if archivedEvents.isEmpty {
                // 長期キャッシュ未取り込み
                VStack(alignment: .leading, spacing: 12) {
                    Text("長期キャッシュが未取り込みのため過去を表示できません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("設定画面で取り込む")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 8)
            } else if !settings.hasAnyEnabled {
                // 設定で全てOFFの場合
                VStack(alignment: .leading, spacing: 12) {
                    Text("関連メモリーの条件が無効になっています")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "gearshape")
                            Text("設定画面で有効化")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 8)
            } else if relatedItems.isEmpty {
                // 該当なし
                Text("関連する過去のエントリーは見つかりませんでした")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                // 関連エントリー一覧
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(relatedItems.enumerated()), id: \.element.event.uid) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        RelatedMemoryRow(item: item)
                    }
                }
            }
        }
        .task {
            await loadRelatedMemories()
        }
    }

    private func loadRelatedMemories() async {
        isLoading = true
        errorMessage = nil

        do {
            let items = try service.findRelatedMemories(
                for: targetDate,
                settings: settings,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            // サービス側でフィルタリング済みだが、念のため再度フィルタリング
            relatedItems = items.filter { enabledCalendarIds.contains($0.event.calendarId) }
        } catch {
            errorMessage = "関連メモリーの読み込みに失敗しました"
        }

        isLoading = false
    }
}

// MARK: - Related Memory Row

private struct RelatedMemoryRow: View {
    let item: RelatedMemoryItem

    var body: some View {
        NavigationLink {
            ArchivedCalendarEventDetailView(
                event: item.event,
                calendar: nil
            )
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // タイトル
                    Text(item.event.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    // 日時
                    HStack(spacing: 4) {
                        if item.event.isAllDay {
                            Text("終日")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(item.event.start, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(item.displayYearText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 一致理由バッジ
                    HStack(spacing: 4) {
                        ForEach(Array(item.matchReasons), id: \.self) { reason in
                            Text(reason.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
