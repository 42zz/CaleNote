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
    @State private var selectedCalendarId: String?
    @State private var isPresentingCalendarPicker = false

    init(entry: JournalEntry? = nil) {
        self.entry = entry
        _title = State(initialValue: entry?.title ?? "")
        _content = State(initialValue: entry?.body ?? "")  // ← body → content
        _eventDate = State(initialValue: entry?.eventDate ?? Date())
        // 初期値：既存エントリの場合はlinkedCalendarId、新規の場合は設定値
        _selectedCalendarId = State(initialValue: entry?.linkedCalendarId ?? JournalWriteSettings.loadWriteCalendarId())
    }

    // 書き込み先カレンダーIDを決定（選択中のカレンダーIDを使用）
    private var targetCalendarId: String? {
        selectedCalendarId ?? JournalWriteSettings.loadWriteCalendarId()
    }

    // 書き込み先カレンダーを取得
    private var targetCalendar: CachedCalendar? {
        guard let calendarId = targetCalendarId else { return nil }
        return calendars.first { $0.calendarId == calendarId }
    }
    
    // 選択可能なカレンダー一覧（有効なカレンダーのみ）
    private var selectableCalendars: [CachedCalendar] {
        calendars.filter { $0.isEnabled }
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
                    DatePicker("日時", selection: $eventDate)
                    TextField("タイトル", text: $title)
                    TextEditor(text: $content)
                        .frame(minHeight: 180)
                } footer: {
                    HStack {
                        Spacer()
                        // 書き込み先カレンダー表示（タップ可能）
                        Text("書き込み先")
                        Button {
                            isPresentingCalendarPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: targetCalendar?.iconName ?? "calendar")
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
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(calendarColor.opacity(0.1))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
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
                    .buttonStyle(.borderedProminent)
                    .tint(Color.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("保存中...")
                            }
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(isSaving)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue)
                }
            }
        }
        .sheet(isPresented: $isPresentingCalendarPicker) {
            CalendarPickerView(
                calendars: selectableCalendars,
                selectedCalendarId: Binding(
                    get: { 
                        if let selected = selectedCalendarId {
                            return selected
                        }
                        return JournalWriteSettings.loadWriteCalendarId()
                    },
                    set: { (newValue: String?) in
                        selectedCalendarId = newValue
                        // 新規作成の場合は設定も更新
                        if entry == nil {
                            JournalWriteSettings.saveWriteCalendarId(newValue)
                        }
                    }
                )
            )
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
            
            // 注意: linkedCalendarIdはsyncOne内で更新するため、ここでは更新しない
            // これにより、syncOne内で古いカレンダーIDを取得できる
            
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
                iconName: calendarIconName,
                linkedCalendarId: targetCalendarId
            )
            modelContext.insert(newEntry)
            targetEntry = newEntry
        }

        Task {
            do {
                // まずローカルに保存
                try modelContext.save()
                
                // 選択したカレンダーIDを使用（なければデフォルト）
                let finalCalendarId = targetCalendarId ?? "primary"
                
                // カレンダー側と同期（同期的に実行）
                try await syncService.syncOne(
                    entry: targetEntry,
                    targetCalendarId: finalCalendarId,
                    auth: auth,
                    modelContext: modelContext
                )
                
                // 同期が完了してから画面を閉じる
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    // 同期失敗時は再送フラグを立てる
                    targetEntry.needsCalendarSync = true
                    try? modelContext.save()
                    
                    saveErrorMessage = "カレンダーへの同期に失敗しました: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }

}
