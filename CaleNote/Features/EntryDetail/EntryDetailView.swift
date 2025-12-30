import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var relatedIndex: RelatedEntriesIndexService
    @EnvironmentObject private var syncService: CalendarSyncService

    let entry: ScheduleEntry

    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            detailsSection
            tagsSection
            syncStatusSection
            actionsSection
            relatedSections
        }
        .listStyle(.plain)
        .navigationTitle("エントリー詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            JournalEditorView(entry: entry, initialDate: entry.startAt)
                .environmentObject(syncService)
                .environmentObject(relatedIndex)
        }
        .alert("削除しますか？", isPresented: $showDeleteAlert) {
            Button("削除", role: .destructive) {
                deleteEntry()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません")
        }
        .onAppear {
            if !relatedIndex.isReady {
                relatedIndex.rebuildIndex(modelContext: modelContext)
            }
        }
    }

    private var detailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(dateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var tagsSection: some View {
        Section {
            if entry.tags.isEmpty {
                Text("タグなし")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }
                    }
                }
            }
        } header: {
            Text("タグ")
        }
    }

    private var syncStatusSection: some View {
        Section {
            HStack(spacing: 8) {
                if let statusIcon = syncStatusIcon {
                    Image(systemName: statusIcon.name)
                        .foregroundColor(statusIcon.color)
                }
                Text(syncStatusText)
            }
            .font(.subheadline)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("同期状態")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showEditSheet = true
            } label: {
                Label("編集", systemImage: "pencil")
            }

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("削除", systemImage: "trash")
            }
            .disabled(isDeleting)
        }
    }

    @ViewBuilder
    private var relatedSections: some View {
        let related = relatedIndex.relatedEntries(for: entry)

        if related.isEmpty {
            Section("関連エントリー") {
                Text("該当なし")
                    .foregroundStyle(.secondary)
            }
        } else {
            if !related.sameMonthDay.isEmpty {
                Section("同じ月日") {
                    ForEach(related.sameMonthDay) { item in
                        NavigationLink {
                            EntryDetailView(entry: item)
                        } label: {
                            TimelineRowView(entry: item)
                        }
                    }
                }
            }

            if !related.sameWeekdayInWeek.isEmpty {
                Section("同じ週の同じ曜日") {
                    ForEach(related.sameWeekdayInWeek) { item in
                        NavigationLink {
                            EntryDetailView(entry: item)
                        } label: {
                            TimelineRowView(entry: item)
                        }
                    }
                }
            }

            if let holidaySection = related.sameHoliday {
                Section("同じ祝日（\(holidaySection.holiday.name)）") {
                    ForEach(holidaySection.entries) { item in
                        NavigationLink {
                            EntryDetailView(entry: item)
                        } label: {
                            TimelineRowView(entry: item)
                        }
                    }
                }
            }
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = entry.isAllDay ? .none : .short
        if entry.isAllDay {
            return "\(formatter.string(from: entry.startAt))（終日）"
        }
        let endFormatter = DateFormatter()
        endFormatter.dateStyle = .none
        endFormatter.timeStyle = .short
        return "\(formatter.string(from: entry.startAt)) - \(endFormatter.string(from: entry.endAt))"
    }

    private var syncStatusText: String {
        switch entry.syncStatus {
        case ScheduleEntry.SyncStatus.pending.rawValue:
            return "同期待ち"
        case ScheduleEntry.SyncStatus.failed.rawValue:
            return "同期失敗"
        default:
            return "同期済み"
        }
    }

    private var syncStatusIcon: (name: String, color: Color)? {
        switch entry.syncStatus {
        case ScheduleEntry.SyncStatus.pending.rawValue:
            return ("arrow.clockwise.circle.fill", .orange)
        case ScheduleEntry.SyncStatus.failed.rawValue:
            return ("exclamationmark.circle.fill", .red)
        case ScheduleEntry.SyncStatus.synced.rawValue:
            return ("checkmark.circle.fill", .green)
        default:
            return nil
        }
    }

    private func deleteEntry() {
        if isDeleting { return }
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                try await syncService.deleteEntry(entry)
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "削除に失敗しました: \(error.localizedDescription)"
                    isDeleting = false
                }
            }
        }
    }
}
