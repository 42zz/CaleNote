import SwiftUI
import SwiftData

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ヘッダー部分（カラーバー）
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        // カラーバー（左側）
                        Rectangle()
                            .fill(displayColor)
                            .frame(width: 4)
                            .padding(.trailing, 12)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.title2)
                                .bold()

                            if event.isAllDay {
                                Text("終日")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(event.start, style: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }

                // アーカイブ表示のバッジ
                // HStack {
                //     Label("長期キャッシュ", systemImage: "archivebox.fill")
                //         .font(.caption)
                //         .foregroundStyle(.secondary)
                //         .padding(.horizontal, 8)
                //         .padding(.vertical, 4)
                //         .background(Color.secondary.opacity(0.1))
                //         .cornerRadius(8)
                // }

                // 日時セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("日時")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 4) {
                        if event.isAllDay {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                Text(formatDate(event.start))
                            }
                        } else {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                if let end = event.end {
                                    Text("\(formatDateTime(event.start)) 〜 \(formatDateTime(end))")
                                } else {
                                    Text(formatDateTime(event.start))
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }

                // 説明セクション
                if let desc = event.desc, !desc.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("説明")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(desc)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

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
                            value: formatDateTime(event.cachedAt)
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
        .navigationTitle("カレンダーイベント")
        .navigationBarTitleDisplayMode(.inline)
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
           let uuid = UUID(uuidString: journalIdString) {
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

// メタデータ行のコンポーネント
private struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)

            Spacer()
        }
    }
}

