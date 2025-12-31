//
//  SidebarView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI
import SwiftData

/// サイドバービュー
///
/// カレンダーリストの表示/非表示設定と設定へのアクセスを提供する。
struct SidebarView: View {
    // MARK: - Environment

    @EnvironmentObject private var calendarListService: CalendarListService

    // MARK: - State

    @Binding var showSettings: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            sidebarHeader

            Divider()

            // カレンダーリスト
            calendarList

            Divider()

            // フッター（設定、フィードバック）
            sidebarFooter
        }
        .frame(width: 280)
        .background(Color.cnBackground)
        .accessibilityIdentifier("sidebarView")
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack {
            Text(L10n.tr("sidebar.title"))
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            if calendarListService.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                    .accessibilityLabel(L10n.tr("sync.in_progress"))
            } else {
                Button {
                    Task {
                        await calendarListService.syncCalendarList()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                }
                .accessibilityLabel(L10n.tr("sidebar.sync_calendars"))
                .accessibilityHint(L10n.tr("sidebar.sync_calendars.hint"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Calendar List

    private var calendarList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(calendarListService.calendars, id: \.calendarId) { calendar in
                    CalendarRowView(
                        calendar: calendar,
                        onToggleVisibility: {
                            calendarListService.toggleCalendarVisibility(calendar.calendarId)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("sidebarCalendarList")
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .frame(width: 24, height: 24)

                    Text(L10n.tr("common.settings"))

                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .accessibilityIdentifier("sidebarSettingsButton")

            Button {
                // フィードバック送信
                if let url = URL(string: "mailto:feedback@example.com") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .frame(width: 24, height: 24)

                    Text(L10n.tr("common.feedback"))

                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .accessibilityHint(L10n.tr("feedback.email.hint"))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Calendar Row View

/// カレンダー行ビュー
private struct CalendarRowView: View {
    let calendar: CalendarInfo
    let onToggleVisibility: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            onToggleVisibility()
        } label: {
            HStack(spacing: 12) {
                // チェックボックス
                Image(systemName: calendar.isVisible ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundColor(calendar.isVisible ? calendarColor : .secondary)

                // カラーインジケーター
                Circle()
                    .fill(calendarColor)
                    .frame(width: 12, height: 12)

                // カレンダー名
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(calendar.summary)
                            .font(.subheadline)

                        // プライマリバッジ
                        if calendar.isPrimary {
                            Text(L10n.tr("calendar.primary"))
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }

                        // 読み取り専用バッジ
                        if calendar.isReadOnly {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendar.summary)
        .accessibilityValue(calendarAccessibilityValue)
        .accessibilityHint(L10n.tr("calendar.visibility.toggle.hint"))
        .accessibilityIdentifier("calendarRow_\(calendar.calendarId)")
    }

    private var calendarAccessibilityValue: String {
        var parts = [calendar.isVisible ? L10n.tr("common.visible") : L10n.tr("common.hidden")]
        if calendar.isPrimary {
            parts.append(L10n.tr("calendar.primary"))
        }
        if calendar.isReadOnly {
            parts.append(L10n.tr("calendar.read_only"))
        }
        return parts.joined(separator: L10n.tr("common.list_separator"))
    }

    private var calendarColor: Color {
        CalendarColor.color(from: calendar.backgroundColor, colorScheme: colorScheme)
    }
}

// MARK: - Color Extension

extension Color {
    /// 16進数カラーコードからColorを生成
    /// - Parameter hex: 16進数カラーコード（#付きまたはなし、例: "#FF6B6B" or "FF6B6B"）
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)

        // #を除去
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        // 6文字のHEXを期待
        guard hexString.count == 6 else {
            return nil
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgbValue) else {
            return nil
        }

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
