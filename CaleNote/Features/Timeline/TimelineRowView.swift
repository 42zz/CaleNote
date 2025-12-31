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
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Properties

    let entry: ScheduleEntry
    let showTags: Bool
    let displayDate: Date?

    init(entry: ScheduleEntry, showTags: Bool = true, displayDate: Date? = nil) {
        self.entry = entry
        self.showTags = showTags
        self.displayDate = displayDate
    }

    // MARK: - Calendar Color

    /// カレンダーの背景色
    private var calendarColor: Color {
        CalendarColor.color(
            from: calendarListService.backgroundColor(for: entry.calendarId),
            colorScheme: colorScheme
        )
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
            return L10n.tr("sync.status.pending")
        case ScheduleEntry.SyncStatus.failed.rawValue:
            return L10n.tr("sync.status.failed")
        default:
            return L10n.tr("sync.status.synced")
        }
    }

    /// ソースバッジ
    private var sourceIcon: String {
        entry.managedByCaleNote ? "note.text" : "calendar"
    }

    private var sourceText: String {
        entry.managedByCaleNote ? L10n.tr("source.calenote") : L10n.tr("source.google_calendar")
    }

    private struct AllDaySpanContext {
        let isStart: Bool
        let isMiddle: Bool
        let isEnd: Bool
        let rangeText: String
    }

    private var allDaySpanContext: AllDaySpanContext? {
        guard entry.isAllDay, entry.isMultiDayAllDay, let displayDate else { return nil }
        let calendar = Calendar.current
        let span = entry.allDaySpan(using: calendar)
        guard let lastDay = calendar.date(byAdding: .day, value: span.dayCount - 1, to: span.startDay) else {
            return nil
        }
        let isStart = calendar.isDate(displayDate, inSameDayAs: span.startDay)
        let isEnd = calendar.isDate(displayDate, inSameDayAs: lastDay)
        let isMiddle = !isStart && !isEnd
        return AllDaySpanContext(
            isStart: isStart,
            isMiddle: isMiddle,
            isEnd: isEnd,
            rangeText: allDayRangeText(span: span, lastDay: lastDay)
        )
    }

    private func allDayRangeText(span: (startDay: Date, endDayExclusive: Date, dayCount: Int), lastDay: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: span.startDay)) - \(formatter.string(from: lastDay))"
    }

    private var allDayContinuationLabel: String? {
        guard let context = allDaySpanContext else { return nil }
        if context.isMiddle {
            return L10n.tr("timeline.all_day.continues")
        }
        if context.isEnd {
            return L10n.tr("timeline.all_day.last_day")
        }
        if context.isStart {
            return L10n.tr("timeline.all_day.start")
        }
        return nil
    }

    private var accessibilityLabelText: String {
        var parts: [String] = [entry.title]
        if entry.isAllDay {
            parts.append(L10n.tr("timeline.all_day"))
            if let label = allDayContinuationLabel {
                parts.append(label)
            }
        } else {
            parts.append(L10n.tr("timeline.accessibility.start_time", timeText))
            parts.append(L10n.tr("timeline.accessibility.end_time", endTimeText))
        }
        if let body = entry.body, !body.isEmpty {
            parts.append(L10n.tr("timeline.accessibility.has_body"))
        }
        if !entry.tags.isEmpty {
            let tagText = entry.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
            parts.append(L10n.tr("timeline.accessibility.tags", tagText))
        }
        return parts.joined(separator: L10n.tr("common.list_separator"))
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
                    Text(L10n.tr("timeline.all_day"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let label = allDayContinuationLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
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

                if let spanContext = allDaySpanContext {
                    Text(L10n.tr("timeline.all_day.range", spanContext.rangeText))
                        .font(.caption2)
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
                                Text(L10n.tr("timeline.tags.more", entry.tags.count - 3))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(entry.isAllDay ? Color.accentColor.opacity(accessibilityContrast == .high ? 0.2 : 0.08) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(entry.isAllDay ? Color.accentColor.opacity(accessibilityContrast == .high ? 0.6 : 0.2) : .clear, lineWidth: entry.isAllDay ? 1 : 0)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(L10n.tr("timeline.accessibility.value", syncStatusText, sourceText))
        .accessibilityIdentifier("timelineRow_\(entry.title)")
    }
}
