import SwiftData
import SwiftUI

struct TimelineRowView: View {
  let item: TimelineItem

  // ジャーナル詳細へ遷移するために参照が必要
  let journalEntry: JournalEntry?

  // 削除処理（必要なら）
  let onDeleteJournal: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(item.title)
          .font(.headline)

        if item.kind == .calendar {
          Spacer()
          Image(systemName: "calendar")
            .foregroundStyle(.secondary)
        }
      }

      if let bodyText = item.body, !bodyText.isEmpty {
        Text(bodyText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Text(item.date, style: .time)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
    .swipeActions(edge: .trailing) {
      if item.kind == .journal, onDeleteJournal != nil {
        Button(role: .destructive) {
          onDeleteJournal?()
        } label: {
          Label("削除", systemImage: "trash")
        }
      }
    }
  }
}
