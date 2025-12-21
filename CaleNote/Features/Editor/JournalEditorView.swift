import SwiftData
import SwiftUI

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var auth: GoogleAuthService
    private let syncService = JournalCalendarSyncService()

    private let entry: JournalEntry?

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

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("タイトル（任意）", text: $title)
                    DatePicker("日時", selection: $eventDate)
                }

                Section("本文（必須）") {
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

        let trimmedBody = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            errorMessage = "本文は必須です。"
            isSaving = false
            return
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = normalizedTitle.isEmpty ? nil : normalizedTitle

        // ここで必ず「保存対象」を1つに決める
        let targetEntry: JournalEntry
        if let entry {
            targetEntry = entry
            targetEntry.title = finalTitle
            targetEntry.body = trimmedBody
            targetEntry.eventDate = eventDate
            targetEntry.updatedAt = Date()
        } else {
            let newEntry = JournalEntry(
                title: finalTitle,
                body: trimmedBody,
                eventDate: eventDate,
                createdAt: Date(),
                updatedAt: Date()
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
