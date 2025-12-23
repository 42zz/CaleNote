import SwiftData
import SwiftUI

struct TimelineRowLink: View {
    let item: TimelineItem
    let entry: JournalEntry?
    let calendarEvent: CachedCalendarEvent?
    let archivedEvent: ArchivedCalendarEvent?
    let calendar: CachedCalendar?
    let isResendingIndividual: Bool
    let resendingEntryId: String?
    let isFirstItemInFirstSection: Bool
    let isLastItemInLastSection: Bool
    let onSyncBadgeTap: (() -> Void)?
    let onDeleteJournal: ((JournalEntry) -> Void)?
    let onDeleteCalendar: ((CachedCalendarEvent) -> Void)?

    var body: some View {
        NavigationLink {
            if let entry {
                JournalDetailView(entry: entry)
            } else if let calendarEvent {
                CalendarEventDetailView(event: calendarEvent, calendar: calendar)
            } else if let archivedEvent {
                ArchivedCalendarEventDetailView(event: archivedEvent, calendar: calendar)
            } else {
                Text("詳細を表示できません")
            }
        } label: {
            TimelineRowView(
                item: item,
                journalEntry: entry,
                onDeleteJournal: nil,
                onSyncBadgeTap: onSyncBadgeTap,
                syncingEntryId: isResendingIndividual ? resendingEntryId : nil
            )
            .padding(.top, isFirstItemInFirstSection ? 8 : 0)
            .padding(.bottom, isLastItemInLastSection ? 8 : 0)
        }
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            if let entry {
                Button(role: .destructive) {
                    onDeleteJournal?(entry)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            } else if let calendarEvent {
                Button(role: .destructive) {
                    onDeleteCalendar?(calendarEvent)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
            // アーカイブイベントは削除不可（読み取り専用）
        }
    }
}

