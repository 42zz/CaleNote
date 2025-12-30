import SwiftData
import SwiftUI

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var searchIndex: SearchIndexService
    // Use EnvironmentObject for SyncService if possible, or create local/singleton. 
    // Usually services should be injected. Assuming it's available or we create one.
    // Given the previous files, CalendarSyncService is likely created in App and injected.
    // Let's assume it's injected or we can access it. 
    // But for now, let's look at how TimelineView accesses it.
    // If not injected, we might need to instantiate or use a singleton if we made one.
    // CalendarSyncService is ObservableObject, so likely EnvironmentObject.
    @EnvironmentObject private var syncService: CalendarSyncService

    private let entry: ScheduleEntry?
    private let initialDate: Date

    @Query(sort: \ScheduleEntry.startAt, order: .reverse)
    private var allEntries: [ScheduleEntry]

    @State private var title: String
    @State private var bodyText: String
    @State private var startAt: Date
    @State private var isAllDay: Bool

    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Tag suggestions
    private var suggestedTags: [String] {
        var tagCounts: [String: Int] = [:]
        for entry in allEntries {
            for tag in entry.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    // Current partial tag for autocomplete
    private var currentPartialTag: String? {
        guard let hashIndex = bodyText.lastIndex(of: "#") else { return nil }
        let afterHash = String(bodyText[bodyText.index(after: hashIndex)...])
        if afterHash.contains(where: { $0.isWhitespace }) {
            return nil
        }
        return afterHash
    }
    
    private var filteredTagSuggestions: [String] {
        guard let partial = currentPartialTag else { return [] }
        if partial.isEmpty {
            return suggestedTags
        }
        return suggestedTags.filter { $0.lowercased().hasPrefix(partial.lowercased()) }
    }

    init(entry: ScheduleEntry? = nil, initialDate: Date = Date()) {
        self.entry = entry
        self.initialDate = initialDate
        _title = State(initialValue: entry?.title ?? "")
        _bodyText = State(initialValue: entry?.body ?? "")
        _startAt = State(initialValue: entry?.startAt ?? initialDate)
        _isAllDay = State(initialValue: entry?.isAllDay ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日時", selection: $startAt)
                    Toggle("終日", isOn: $isAllDay)
                    TextField("タイトル", text: $title)
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 180)
                        
                        // Tag Suggestions
                        if !filteredTagSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(filteredTagSuggestions, id: \.self) { tag in
                                        Button("#\(tag)") {
                                            insertTag(tag)
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }
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
        errorMessage = nil

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let endAt = isAllDay ? startAt : startAt.addingTimeInterval(3600) // Default 1 hour
        let extractedTags = TagExtractor.extract(from: bodyText)

        Task {
            do {
                var createdEntry: ScheduleEntry?
                if let entry {
                    // Update existing
                    entry.title = finalTitle.isEmpty ? "(タイトルなし)" : finalTitle
                    entry.body = bodyText
                    entry.startAt = startAt
                    entry.endAt = endAt
                    entry.isAllDay = isAllDay
                    entry.tags = extractedTags
                    entry.syncStatus = ScheduleEntry.SyncStatus.pending.rawValue
                    entry.updatedAt = Date()
                } else {
                    // Create new
                    let newEntry = ScheduleEntry(
                        source: ScheduleEntry.Source.calenote.rawValue,
                        managedByCaleNote: true,
                        startAt: startAt,
                        endAt: endAt,
                        isAllDay: isAllDay,
                        title: finalTitle.isEmpty ? "(タイトルなし)" : finalTitle,
                        body: bodyText,
                        tags: extractedTags,
                        syncStatus: ScheduleEntry.SyncStatus.pending.rawValue
                    )
                    modelContext.insert(newEntry)
                    createdEntry = newEntry
                }
                
                try modelContext.save()

                if let entry {
                    searchIndex.updateEntry(entry)
                } else if let createdEntry {
                    searchIndex.indexEntry(createdEntry)
                }
                
                // Trigger sync
                try await syncService.syncLocalChangesToGoogle()
                
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "保存失敗: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
    
    private func insertTag(_ tag: String) {
        guard let hashIndex = bodyText.lastIndex(of: "#") else { return }
        let beforeHash = String(bodyText[..<hashIndex])
        bodyText = beforeHash + "#" + tag + " "
    }
}
