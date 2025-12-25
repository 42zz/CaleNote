import SwiftData
import SwiftUI

struct ArchivedCalendarEventDetailView: View {
    let event: ArchivedCalendarEvent
    let calendar: CachedCalendar?

    @Environment(\.modelContext) private var modelContext
    @Query private var cachedCalendars: [CachedCalendar]
    @State private var isPresentingEditor = false
    @State private var journalEntryForEdit: JournalEntry?
    @State private var enabledCalendarIds: Set<String> = []
    @State private var hasArchivedEvents = false
    @State private var tags: [String] = []
    @State private var descriptionWithoutTagsCache: String = ""

    // キャッシュ化されたcomputed properties（body再評価で毎回計算しない）
    @State private var correctCalendar: CachedCalendar? = nil
    @State private var displayColor: Color = .blue
    @State private var calendarColorHex: String = "#3B82F6"
    @State private var calendarIconName: String = "calendar"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー部分
                DetailHeaderView(
                    title: event.title,
                    displayColor: displayColor,
                    showColorBar: false
                )

                // 説明セクション
                DetailDescriptionSection(
                    text: descriptionWithoutTagsCache,
                    tags: tags,
                    displayColor: displayColor
                )

                // メタ情報（カレンダー所属・同期状態・追加情報）
                DetailMetadataSection(
                    calendarName: correctCalendar?.summary,
                    syncStatus: (event.status == "confirmed" && !event.eventId.isEmpty)
                        ? .synced : .none,
                    displayColor: displayColor,
                    lastSyncedAt: (event.status == "confirmed" && !event.eventId.isEmpty)
                        ? event.cachedAt : nil,
                    additionalMetadata: {
                        var metadata: [DetailMetadataSection.AdditionalMetadataItem] = []

                        // ステータス
                        if event.status != "confirmed" {
                            metadata.append(
                                .init(
                                    icon: "xmark.circle.fill",
                                    label: "同期済み",
                                    value: "未同期",
                                    valueColor: .red
                                ))
                        }

                        return metadata
                    }()
                )

                // 関連する過去セクション
                RelatedMemoriesSection(
                    targetDate: event.start,
                    enabledCalendarIds: enabledCalendarIds,
                    hasArchivedEvents: hasArchivedEvents
                )
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            // enabledCalendarIds の初期化を最優先で実行（RelatedMemoriesSection が依存するため）
            updateEnabledCalendarIds()
            // 重い処理は Task 内で実行
            updateCachedData()
        }
        .onChange(of: cachedCalendars) { _, _ in
            // カレンダーリスト変更時は即座に更新
            updateEnabledCalendarIds()
        }
        .onChange(of: event.desc) { _, _ in
            // 説明文変更時のみキャッシュ更新
            updateCachedData()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationDateTimeView(
                    eventDate: event.start,
                    isAllDay: event.isAllDay,
                    endDate: event.end,
                    displayColor: displayColor
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: prepareEditJournal) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text("編集")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.blue)
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            if let entry = journalEntryForEdit {
                JournalEditorView(entry: entry)
            }
        }
    }

    private func prepareEditJournal() {
        // 既存のジャーナルを取得または新規作成
        if let journalIdString = event.linkedJournalId,
            let uuid = UUID(uuidString: journalIdString)
        {
            // 紐づいているジャーナルを取得
            let predicate = #Predicate<JournalEntry> { $0.id == uuid }
            let descriptor = FetchDescriptor(predicate: predicate)
            if let existingEntry = try? modelContext.fetch(descriptor).first {
                journalEntryForEdit = existingEntry
                isPresentingEditor = true
                return
            }
        }

        // 紐づいているジャーナルがない場合は新規作成
        // カレンダーの色とアイコンを使用（キャッシュ済み）
        let newEntry = JournalEntry(
            title: event.title.isEmpty ? nil : event.title,
            body: event.desc ?? "",
            eventDate: event.start,
            colorHex: calendarColorHex,
            iconName: calendarIconName,
            linkedCalendarId: event.calendarId,
            linkedEventId: event.eventId,
            linkedEventUpdatedAt: event.updatedAt,
            needsCalendarSync: false
        )
        modelContext.insert(newEntry)
        try? modelContext.save()

        // アーカイブイベント側にもリンクを設定
        event.linkedJournalId = newEntry.id.uuidString
        try? modelContext.save()

        journalEntryForEdit = newEntry
        isPresentingEditor = true
    }

    private func updateEnabledCalendarIds() {
        let newIds = Set(cachedCalendars.filter { $0.isEnabled }.map { $0.calendarId })
        // 差分がある場合のみ更新
        if newIds != enabledCalendarIds {
            enabledCalendarIds = newIds
            print("📝 ArchivedCalendarEventDetailView: enabledCalendarIds更新 件数=\(newIds.count)")
        }
    }

    private func updateCachedData() {
        // 重い処理をTask内で実行してメインスレッドブロックを防ぐ
        Task { @MainActor in
            // correctCalendar計算（body評価で毎回first { }しない）
            correctCalendar = cachedCalendars.first { $0.calendarId == event.calendarId }

            // displayColor計算
            if let hex = correctCalendar?.userColorHex {
                displayColor = Color(hex: hex) ?? .blue
            } else {
                displayColor = .blue
            }

            // prepareEditJournalで使う値をキャッシュ
            calendarColorHex = correctCalendar?.userColorHex ?? "#3B82F6"
            calendarIconName = correctCalendar?.iconName ?? "calendar"

            // タグ抽出（@Stateにキャッシュして毎回計算しない）
            guard let desc = event.desc, !desc.isEmpty else {
                tags = []
                descriptionWithoutTagsCache = ""
                hasArchivedEvents = false
                return
            }

            let newTags = TagExtractionUtility.extractTags(from: desc)
            if newTags != tags {
                tags = newTags
            }

            // タグ除去済み本文（@Stateにキャッシュして毎回計算しない）
            let newDescWithoutTags = TagExtractionUtility.removeTags(from: desc)
            if newDescWithoutTags != descriptionWithoutTagsCache {
                descriptionWithoutTagsCache = newDescWithoutTags
            }

            // hasArchivedEventsの確認（軽量なカウントクエリ）
            let descriptor = FetchDescriptor<ArchivedCalendarEvent>()
            if let count = try? modelContext.fetchCount(descriptor), count > 0 {
                hasArchivedEvents = true
            } else {
                hasArchivedEvents = false
            }
        }
    }
}
