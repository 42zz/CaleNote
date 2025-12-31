import SwiftData
import SwiftUI
import UIKit

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var searchIndex: SearchIndexService
    @EnvironmentObject private var relatedIndex: RelatedEntriesIndexService
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

    @State private var title: String
    @State private var bodyText: String
    @State private var startAt: Date
    @State private var isAllDay: Bool

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSaveSuccess = false
    
    // Tag suggestions
    private var suggestedTags: [String] {
        searchIndex.tagSuggestions(limit: 10)
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
                    DatePicker(
                        L10n.tr("editor.datetime"),
                        selection: $startAt,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                        .accessibilityIdentifier("entryDatePicker")
                    Toggle(L10n.tr("editor.all_day"), isOn: $isAllDay)
                        .accessibilityIdentifier("entryAllDayToggle")
                        .onChange(of: isAllDay) { _, newValue in
                            adjustStartAtForAllDayChange(isAllDay: newValue)
                        }
                    TextField(L10n.tr("editor.title"), text: $title)
                        .accessibilityIdentifier("entryTitleField")
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 180)
                            .accessibilityLabel(L10n.tr("editor.body"))
                            .accessibilityHint(L10n.tr("editor.body.hint"))
                            .accessibilityIdentifier("entryBodyEditor")
                        
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
            .overlay(alignment: .top) {
                if showSaveSuccess {
                    SuccessToastView(message: L10n.tr("editor.save.success"))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(entry == nil ? L10n.tr("editor.new") : L10n.tr("common.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.cancel")) { dismiss() }
                        .accessibilityIdentifier("entryCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(L10n.tr("editor.save.in_progress"))
                            }
                        } else {
                            Text(L10n.tr("common.save"))
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("entrySaveButton")
                }
            }
        }
    }

    private func save() {
        if isSaving { return }
        isSaving = true
        errorMessage = nil
        showSaveSuccess = false

        let calendar = Calendar.current
        let normalizedStartAt = isAllDay ? calendar.startOfDay(for: startAt) : startAt
        let finalTitle = InputValidator.sanitizeTitle(title)
        let finalBody = InputValidator.sanitizeBody(bodyText)
        if let validationError = InputValidator.validate(title: finalTitle, body: finalBody) {
            errorMessage = validationError
            isSaving = false
            return
        }
        let endAt: Date
        if isAllDay {
            endAt = calendar.date(byAdding: .day, value: 1, to: normalizedStartAt) ?? normalizedStartAt
        } else {
            endAt = normalizedStartAt.addingTimeInterval(3600) // Default 1 hour
        }
        let extractedTags = TagParser.extract(from: [finalTitle, finalBody])

        Task {
            do {
                var createdEntry: ScheduleEntry?
                if let entry {
                    // Update existing
                    entry.title = finalTitle.isEmpty ? L10n.tr("editor.untitled") : finalTitle
                    entry.body = finalBody
                    entry.startAt = normalizedStartAt
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
                        startAt: normalizedStartAt,
                        endAt: endAt,
                        isAllDay: isAllDay,
                        title: finalTitle.isEmpty ? L10n.tr("editor.untitled") : finalTitle,
                        body: finalBody,
                        tags: extractedTags,
                        syncStatus: ScheduleEntry.SyncStatus.pending.rawValue
                    )
                    modelContext.insert(newEntry)
                    createdEntry = newEntry
                }
                
                try modelContext.save()

                if let entry {
                    searchIndex.updateEntry(entry)
                    relatedIndex.updateEntry(entry)
                } else if let createdEntry {
                    searchIndex.indexEntry(createdEntry)
                    relatedIndex.indexEntry(createdEntry)
                }
                
                // Trigger sync
                try await syncService.syncLocalChangesToGoogle()
                
                await MainActor.run {
                    isSaving = false
                    showSaveSuccess = true
                    UIAccessibility.post(notification: .announcement, argument: L10n.tr("editor.save.success"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = L10n.tr("editor.save.failed", error.localizedDescription)
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

    private func adjustStartAtForAllDayChange(isAllDay: Bool) {
        let calendar = Calendar.current
        if isAllDay {
            startAt = calendar.startOfDay(for: startAt)
            return
        }

        let components = calendar.dateComponents([.year, .month, .day], from: startAt)
        var normalized = DateComponents()
        normalized.year = components.year
        normalized.month = components.month
        normalized.day = components.day
        normalized.hour = 9
        normalized.minute = 0
        startAt = calendar.date(from: normalized) ?? startAt
    }
}

private struct SuccessToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.semibold)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.isStaticText)
            .padding(.top, 8)
    }
}
