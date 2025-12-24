import SwiftData
import SwiftUI

struct TimelineRowView: View {
  let item: TimelineItem

  // ジャーナル詳細へ遷移するために参照が必要
  let journalEntry: JournalEntry?

  // 削除処理（必要なら）
  let onDeleteJournal: (() -> Void)?

  // 同期バッジタップ時のコールバック
  let onSyncBadgeTap: (() -> Void)?
  
  // 同期中のエントリーID（同期中かどうかを判定するため）
  let syncingEntryId: String?

  // 表示色（統一カードの視覚的整合性のため）
  private var displayColor: Color {
    if let color = Color(hex: item.colorHex) {
      return color
    }
    // デフォルト値（ミュートブルー）
    return Color(hex: "#3B82F6") ?? .blue
  }

  var body: some View {
    HStack(spacing: 0) {
      // カラーバー（左側）
      Rectangle()
        .fill(displayColor)
        .frame(width: 4)

      // コンテンツ
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(item.title)
            .font(.headline)

          Spacer()

          // 同期状態バッジ（ジャーナルのみ）
          if item.kind == .journal, let entry = journalEntry {
            syncStatusBadge(for: entry)
          }
        }

        if let bodyText = item.body, !bodyText.isEmpty {
          Text(bodyText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        // サブテキスト（時間・場所の整合）
        if item.isAllDay {
          Text("終日")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(item.date, style: .time)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 12)
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

  @ViewBuilder
  private func syncStatusBadge(for entry: JournalEntry) -> some View {
    // 優先順位: 同期中 → 競合 → 同期失敗 → 同期済み（何も表示しない）
    let isSyncing = syncingEntryId == entry.id.uuidString
    
    if isSyncing {
      // 同期中バッジ（グルグル回るアイコン）
      SyncingIconView()
    } else if entry.hasConflict {
      // 競合バッジ
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .font(.caption)
        .onTapGesture {
          onSyncBadgeTap?()
        }
    } else if entry.needsCalendarSync {
      // 同期失敗バッジ
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(.yellow)
        .font(.caption)
        .onTapGesture {
          onSyncBadgeTap?()
        }
    }
    // 同期済みの場合は何も表示しない
  }
}

// 同期中アイコンの回転アニメーション用ビュー
private struct SyncingIconView: View {
  @State private var rotation: Double = 0
  
  var body: some View {
    Image(systemName: "arrow.triangle.2.circlepath")
      .foregroundStyle(.blue)
      .font(.caption)
      .rotationEffect(.degrees(rotation))
      .onAppear {
        // 連続的に回転させる
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
          rotation = 360
        }
      }
      .onDisappear {
        rotation = 0
      }
  }
}
