import SwiftUI
import SwiftData

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let entry: JournalEntry?

    @State private var title: String
    @State private var content: String   // ← ここを body から改名
    @State private var eventDate: Date

    @State private var errorMessage: String?

    init(entry: JournalEntry? = nil) {
        self.entry = entry
        _title = State(initialValue: entry?.title ?? "")
        _content = State(initialValue: entry?.body ?? "")   // ← body → content
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
                    TextEditor(text: $content)              // ← body → content
                        .frame(minHeight: 180)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
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
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        let trimmedBody = content.trimmingCharacters(in: .whitespacesAndNewlines) // ← body → content
        if trimmedBody.isEmpty {
            errorMessage = "本文は必須です。"
            return
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = normalizedTitle.isEmpty ? nil : normalizedTitle

        if let entry {
            entry.title = finalTitle
            entry.body = trimmedBody
            entry.eventDate = eventDate
            entry.updatedAt = Date()
        } else {
            let newEntry = JournalEntry(
                title: finalTitle,
                body: trimmedBody,
                eventDate: eventDate,
                createdAt: Date(),
                updatedAt: Date()
            )
            modelContext.insert(newEntry)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
