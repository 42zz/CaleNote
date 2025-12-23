import SwiftData
import SwiftUI

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var auth: GoogleAuthService
    private let syncService = JournalCalendarSyncService()

    private let entry: JournalEntry?

    @Query private var calendars: [CachedCalendar]

    @State private var title: String
    @State private var content: String  // ← ここを body から改名
    @State private var eventDate: Date

    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var errorMessage: String?

    init(entry: JournalEntry? = nil) {
        self.entry = entry
        _title = State(initialValue: entry?.title ?? "")
        _content = State(initialValue: entry?.body ?? "")  // ← body → content
        _eventDate = State(initialValue: entry?.eventDate ?? Date())
    }

    // 書き込み先カレンダーIDを決定（既存エントリはlinkedCalendarId、新規は設定値）
    private var targetCalendarId: String? {
        if let entry = entry, let linkedId = entry.linkedCalendarId {
            return linkedId
        }
        return JournalWriteSettings.loadWriteCalendarId()
    }

    // 書き込み先カレンダーを取得
    private var targetCalendar: CachedCalendar? {
        guard let calendarId = targetCalendarId else { return nil }
        return calendars.first { $0.calendarId == calendarId }
    }

    // カレンダーの表示色
    private var calendarColor: Color {
        if let hex = targetCalendar?.userColorHex {
            return Color(hex: hex) ?? .blue
        }
        return .blue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル（任意）", text: $title)
                    DatePicker("日時", selection: $eventDate)
                } header: {
                    HStack {
                        Text("基本")
                        Spacer()
                        // 書き込み先カレンダー表示
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(calendarColor)
                            
                            if let calendar = targetCalendar {
                                Text(calendar.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if let calendarId = targetCalendarId {
                                Text(calendarId == "primary" ? "プライマリ" : calendarId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(calendarColor.opacity(0.1))
                        .cornerRadius(4)
                    }
                }

                Section("本文") {
                    Text("本文に #タグ を含めると、タグとして扱います。例: #振り返り #SwiftUI")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $content)
                        .frame(minHeight: 180)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                if let msg = saveErrorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(entry == nil ? "新規作成" : "編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        if isSaving { return }

        isSaving = true
        saveErrorMessage = nil
        errorMessage = nil

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = normalizedTitle.isEmpty ? nil : normalizedTitle

        // ここで必ず「保存対象」を1つに決める
        let targetEntry: JournalEntry
        if let entry {
            targetEntry = entry
            targetEntry.title = finalTitle
            targetEntry.body = content
            targetEntry.eventDate = eventDate
            targetEntry.updatedAt = Date()
            
            // カレンダーの色とアイコンが未設定の場合は更新
            if let targetCalendar = targetCalendar {
                if targetEntry.colorHex.isEmpty || targetEntry.colorHex == "#3B82F6" {
                    targetEntry.colorHex = targetCalendar.userColorHex
                }
                if targetEntry.iconName.isEmpty || targetEntry.iconName == "note.text" {
                    targetEntry.iconName = targetCalendar.iconName
                }
            }
        } else {
            // 新規作成時：作成先カレンダーの色を設定
            let calendarColorHex = targetCalendar?.userColorHex ?? "#3B82F6"
            let calendarIconName = targetCalendar?.iconName ?? "calendar"
            
            let newEntry = JournalEntry(
                title: finalTitle,
                body: content,
                eventDate: eventDate,
                createdAt: Date(),
                updatedAt: Date(),
                colorHex: calendarColorHex,
                iconName: calendarIconName
            )
            modelContext.insert(newEntry)
            targetEntry = newEntry
        }

        do {
            try modelContext.save()
            dismiss()

            Task {
                do {
                    let targetCalendarId = JournalWriteSettings.loadWriteCalendarId() ?? "primary"
                    try await syncService.syncOne(
                        entry: targetEntry,
                        targetCalendarId: targetCalendarId,
                        auth: auth,
                        modelContext: modelContext
                    )
                } catch {
                    await MainActor.run {
                        targetEntry.needsCalendarSync = true
                        try? modelContext.save()
                    }
                }

                await MainActor.run {
                    isSaving = false
                }
            }
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
            isSaving = false
        }
    }

}
