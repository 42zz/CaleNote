import SwiftData
import SwiftUI

struct CalendarEventDetailView: View {
    let event: CachedCalendarEvent
    let calendar: CachedCalendar?

    @Environment(\.modelContext) private var modelContext
    @Query private var cachedCalendars: [CachedCalendar]
    @State private var isPresentingEditor = false
    @State private var journalEntryForEdit: JournalEntry?

    // event.calendarIdから正しいカレンダーを取得
    private var correctCalendar: CachedCalendar? {
        cachedCalendars.first { $0.calendarId == event.calendarId }
    }

    private var displayColor: Color {
        if let hex = correctCalendar?.userColorHex {
            return Color(hex: hex) ?? .blue
        }
        return .blue
    }

    // タグを除去した説明文
    private var descriptionWithoutTags: String {
        guard let desc = event.desc, !desc.isEmpty else { return "" }
        return TagExtractionUtility.removeTags(from: desc)
    }

    // 説明文から抽出したタグ
    private var tags: [String] {
        guard let desc = event.desc, !desc.isEmpty else { return [] }
        return TagExtractionUtility.extractTags(from: desc)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 統合ヘッダー（カード形式 - コンパクト化）
                DetailHeaderView(
                    title: event.title,
                    eventDate: event.start,
                    isAllDay: event.isAllDay,
                    endDate: event.end,
                    displayColor: displayColor,
                    showColorBar: false
                )

                // 説明セクション（本文 - 段落構造を視覚化、常に全文表示）
                DetailDescriptionSection(
                    text: descriptionWithoutTags,
                    tags: tags,
                    displayColor: displayColor
                )

                // メタ情報（カレンダー所属・同期状態）- 関連エントリー直前に配置
                DetailMetadataSection(
                    calendarName: correctCalendar?.summary,
                    syncStatus: (event.status == "confirmed" && !event.eventId.isEmpty) ? .synced : .none,
                    displayColor: displayColor,
                    lastSyncedAt: (event.status == "confirmed" && !event.eventId.isEmpty) ? event.cachedAt : nil
                )

                // 関連する過去セクション
                RelatedMemoriesSection(targetDate: event.start)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: prepareEditJournal) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text("編集")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(displayColor))
                }
                .buttonStyle(.borderless)  // plainよりborderlessの方が効くことがある
                .tint(.clear)  // Toolbarの「色付きボタン化」を抑止
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
        // カレンダーの色とアイコンを取得
        let calendarColorHex = correctCalendar?.userColorHex ?? "#3B82F6"
        let calendarIconName = correctCalendar?.iconName ?? "calendar"

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

        // カレンダーイベント側にもリンクを設定
        event.linkedJournalId = newEntry.id.uuidString
        try? modelContext.save()

        journalEntryForEdit = newEntry
        isPresentingEditor = true
    }
}
