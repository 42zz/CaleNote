import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityContrast) private var accessibilityContrast

    @EnvironmentObject private var relatedIndex: RelatedEntriesIndexService
    @EnvironmentObject private var syncService: CalendarSyncService

    let entry: ScheduleEntry

    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showSkeleton = false
    @AppStorage("trashEnabled") private var trashEnabled = TrashSettings.shared.isEnabled

    var body: some View {
        Group {
            if showSkeleton {
                EntryDetailSkeletonView()
            } else {
                List {
                    detailsSection
                    tagsSection
                    syncStatusSection
                    actionsSection
                    relatedSections
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L10n.tr("entry_detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L10n.tr("common.edit"))
                .accessibilityHint(L10n.tr("entry_detail.edit.hint"))
                .accessibilityIdentifier("entryDetailEditButton")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            JournalEditorView(entry: entry, initialDate: entry.startAt)
                .environmentObject(syncService)
                .environmentObject(relatedIndex)
        }
        .alert(trashEnabled ? L10n.tr("entry_detail.delete.confirm.trash") : L10n.tr("entry_detail.delete.confirm.delete"), isPresented: $showDeleteAlert) {
            Button(trashEnabled ? L10n.tr("trash.move_to_trash") : L10n.tr("common.delete"), role: .destructive) {
                deleteEntry()
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(trashEnabled ? L10n.tr("trash.restore_hint") : L10n.tr("common.irreversible"))
        }
        .onAppear {
            showSkeleton = !relatedIndex.isReady
            if !relatedIndex.isReady {
                relatedIndex.rebuildIndex(modelContext: modelContext)
            }
        }
        .onChange(of: relatedIndex.isReady) { _, newValue in
            showSkeleton = !newValue
        }
        .accessibilityAction(named: L10n.tr("common.edit")) {
            showEditSheet = true
        }
        .accessibilityAction(named: L10n.tr("common.delete")) {
            showDeleteAlert = true
        }
    }

    private var detailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("entryDetailTitle")

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
                Text(L10n.tr("tags.none"))
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
                                        .fill(Color.accentColor.opacity(accessibilityContrast == .high ? 0.25 : 0.12))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.accentColor, lineWidth: accessibilityContrast == .high ? 1 : 0)
                                )
                        }
                    }
                }
            }
        } header: {
            Text(L10n.tr("tags.title"))
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
            .accessibilityElement(children: .combine)
            .accessibilityValueText(syncStatusText)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text(L10n.tr("sync.status.title"))
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showEditSheet = true
            } label: {
                Label(L10n.tr("common.edit"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(trashEnabled ? L10n.tr("trash.move_to_trash") : L10n.tr("common.delete"), systemImage: "trash")
            }
            .disabled(isDeleting)
        }
    }

    @ViewBuilder
    private var relatedSections: some View {
        let related = relatedIndex.relatedEntries(for: entry)

        if related.isEmpty {
            Section {
                Text(L10n.tr("entry_detail.related.none"))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.tr("entry_detail.related.title"))
            }
        } else {
            if !related.sameMonthDay.isEmpty {
                Section {
                    ForEach(related.sameMonthDay) { item in
                        NavigationLink {
                            EntryDetailView(entry: item)
                        } label: {
                            TimelineRowView(entry: item)
                        }
                    }
                } header: {
                    Text(L10n.tr("entry_detail.related.same_month_day"))
                }
            }

            if !related.sameWeekdayInWeek.isEmpty {
                Section {
                    ForEach(related.sameWeekdayInWeek) { item in
                        NavigationLink {
                            EntryDetailView(entry: item)
                        } label: {
                            TimelineRowView(entry: item)
                        }
                    }
                } header: {
                    Text(L10n.tr("entry_detail.related.same_weekday"))
                }
            }

            if let holidaySection = related.sameHoliday {
                Section {
                    ForEach(holidaySection.entries) { item in
                        NavigationLink {
                            EntryDetailView(entry: item)
                        } label: {
                            TimelineRowView(entry: item)
                        }
                    }
                } header: {
                    Text(L10n.tr("entry_detail.related.same_holiday", holidaySection.holiday.localizedName))
                }
            }
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = entry.isAllDay ? .none : .short
        if entry.isAllDay {
            let calendar = Calendar.current
            let span = entry.allDaySpan(using: calendar)
            if span.dayCount > 1,
               let lastDay = calendar.date(byAdding: .day, value: -1, to: span.endDayExclusive) {
                return L10n.tr("entry_detail.all_day_range", formatter.string(from: span.startDay), formatter.string(from: lastDay), L10n.tr("entry_detail.all_day_suffix"))
            }
            return L10n.tr("entry_detail.all_day_single", formatter.string(from: span.startDay), L10n.tr("entry_detail.all_day_suffix"))
        }
        let endFormatter = DateFormatter()
        endFormatter.dateStyle = .none
        endFormatter.timeStyle = .short
        return "\(formatter.string(from: entry.startAt)) - \(endFormatter.string(from: entry.endAt))"
    }

    private var syncStatusText: String {
        switch entry.syncStatus {
        case ScheduleEntry.SyncStatus.pending.rawValue:
            return L10n.tr("sync.status.pending")
        case ScheduleEntry.SyncStatus.failed.rawValue:
            return L10n.tr("sync.status.failed")
        default:
            return L10n.tr("sync.status.synced")
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
                    errorMessage = L10n.tr("entry_detail.delete.failed", error.localizedDescription)
                    isDeleting = false
                }
            }
        }
    }
}
