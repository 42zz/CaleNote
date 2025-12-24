import SwiftData
import SwiftUI

struct ArchivedCalendarEventDetailView: View {
    let event: ArchivedCalendarEvent
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
    
    private var tags: [String] {
        guard let desc = event.desc, !desc.isEmpty else { return [] }
        return TagExtractionUtility.extractTags(from: desc)
    }
    
    private var descriptionWithoutTags: String {
        guard let desc = event.desc, !desc.isEmpty else { return "" }
        return TagExtractionUtility.removeTags(from: desc)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー部分
                DetailHeaderView(
                    title: event.title,
                    eventDate: event.start,
                    isAllDay: event.isAllDay,
                    endDate: event.end,
                    displayColor: displayColor,
                    showColorBar: false
                )

                // 説明セクション
                DetailDescriptionSection(
                    text: descriptionWithoutTags,
                    tags: tags,
                    displayColor: displayColor
                )

                Divider()

                // メタデータセクション
                VStack(alignment: .leading, spacing: 12) {
                    Text("詳細情報")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(spacing: 10) {
                        MetadataRow(
                            icon: "calendar.badge.clock",
                            label: "カレンダー",
                            value: correctCalendar?.summary ?? event.calendarId
                        )

                        MetadataRow(
                            icon: "info.circle",
                            label: "ステータス",
                            value: event.status
                        )

                        if event.linkedJournalId != nil {
                            MetadataRow(
                                icon: "link.circle.fill",
                                label: "連携",
                                value: "ジャーナルと連携済み",
                                valueColor: .blue
                            )
                        }

                        MetadataRow(
                            icon: "clock.arrow.circlepath",
                            label: "キャッシュ日時",
                            value: DetailViewDateFormatter.formatDateTime(event.cachedAt)
                        )

                        if let holidayId = event.holidayId {
                            MetadataRow(
                                icon: "flag.fill",
                                label: "祝日",
                                value: holidayId,
                                valueColor: .red
                            )
                        }
                    }
                }

                Divider()

                // 関連する過去セクション
                RelatedMemoriesSection(targetDate: event.start)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            // タブバーの高さ分のスペースを確保
            Color.clear.frame(height: 80)
        }
        .navigationTitle("カレンダーイベント")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    prepareEditJournal()
                } label: {
                    Image(systemName: "pencil")
                }
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

        // アーカイブイベント側にもリンクを設定
        event.linkedJournalId = newEntry.id.uuidString
        try? modelContext.save()

        journalEntryForEdit = newEntry
        isPresentingEditor = true
    }

}
