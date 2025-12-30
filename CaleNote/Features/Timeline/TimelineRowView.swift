//
//  TimelineRowView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

/// タイムラインのエントリー行
struct TimelineRowView: View {
    // MARK: - Environment

    @EnvironmentObject private var calendarListService: CalendarListService
    @Environment(\.accessibilityContrast) private var accessibilityContrast

    // MARK: - Properties

    let entry: ScheduleEntry
    let showTags: Bool

    init(entry: ScheduleEntry, showTags: Bool = true) {
        self.entry = entry
        self.showTags = showTags
    }

    // MARK: - Calendar Color

    /// カレンダーの背景色
    private var calendarColor: Color {
        guard let hexColor = calendarListService.backgroundColor(for: entry.calendarId) else {
            return .accentColor
        }
        return Color(hex: hexColor) ?? .accentColor
    }

    // MARK: - Computed Properties

    /// 時刻表示
    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: entry.startAt)
    }

    /// 終了時刻表示
    private var endTimeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: entry.endAt)
    }

    /// 同期状態アイコン
    private var syncStatusIcon: (name: String, color: Color)? {
        switch entry.syncStatus {
        case ScheduleEntry.SyncStatus.pending.rawValue:
            return ("arrow.clockwise.circle.fill", .orange)
        case ScheduleEntry.SyncStatus.failed.rawValue:
            return ("exclamationmark.circle.fill", .red)
        default:
            return nil
        }
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

    /// ソースバッジ
    private var sourceIcon: String {
        entry.managedByCaleNote ? "note.text" : "calendar"
    }

    private var sourceText: String {
        entry.managedByCaleNote ? "CaleNote" : "Googleカレンダー"
    }

    private var accessibilityLabelText: String {
        var parts: [String] = [entry.title]
        if entry.isAllDay {
            parts.append("終日")
        } else {
            parts.append("開始 \(timeText)")
            parts.append("終了 \(endTimeText)")
        }
        if let body = entry.body, !body.isEmpty {
            parts.append("本文あり")
        }
        if !entry.tags.isEmpty {
            parts.append("タグ \(entry.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))")
        }
        return parts.joined(separator: "、")
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // カレンダーカラーインジケーター
            RoundedRectangle(cornerRadius: 2)
                .fill(calendarColor)
                .frame(width: 4)
                .padding(.vertical, 2)

            // 時刻表示（全日イベントの場合は「終日」表示）
            VStack(alignment: .trailing, spacing: 2) {
                if entry.isAllDay {
                    Text("終日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(endTimeText)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(minWidth: 50, alignment: .trailing)
            .layoutPriority(1)

            // エントリー内容
            VStack(alignment: .leading, spacing: 4) {
                // タイトル
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.body)
                        .fontWeight(.medium)

                    // ソースアイコン
                    Image(systemName: sourceIcon)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // 同期状態バッジ
                    if let syncStatus = syncStatusIcon {
                        Image(systemName: syncStatus.name)
                            .font(.caption)
                            .foregroundColor(syncStatus.color)
                    }

                    Spacer()
                }

                // 本文プレビュー
                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // タグ
                if showTags && !entry.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(entry.tags.prefix(3), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor.opacity(accessibilityContrast == .high ? 0.25 : 0.1))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.accentColor, lineWidth: accessibilityContrast == .high ? 1 : 0)
                                    )
                            }

                            if entry.tags.count > 3 {
                                Text("+\(entry.tags.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue("\(syncStatusText)、ソース \(sourceText)")
    }
}
