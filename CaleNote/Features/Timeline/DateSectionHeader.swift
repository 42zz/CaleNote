//
//  DateSectionHeader.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

/// 日付セクションヘッダー
struct DateSectionHeader: View {
    // MARK: - Properties

    let date: Date
    let isToday: Bool

    // MARK: - Computed Properties

    /// 日付テキスト
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    /// 相対日付テキスト（"今日"など）
    private var relativeDateText: String? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)

        if calendar.isDate(targetDate, inSameDayAs: today) {
            return "今日"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  calendar.isDate(targetDate, inSameDayAs: yesterday) {
            return "昨日"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(targetDate, inSameDayAs: tomorrow) {
            return "明日"
        }

        return nil
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // 今日の場合はドット表示
            if isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                // 相対日付（今日、昨日、明日）
                if let relativeText = relativeDateText {
                    Text(relativeText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isToday ? .accentColor : .primary)
                }

                // 日付
                Text(dateText)
                    .font(isToday ? .subheadline : .caption)
                    .foregroundColor(isToday ? .accentColor.opacity(0.8) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, isToday ? 12 : 0)
        .padding(.vertical, isToday ? 8 : 4)
        .background(
            isToday
                ? Capsule()
                    .fill(Color.accentColor.opacity(0.1))
                : nil
        )
        .listRowInsets(EdgeInsets())
    }
}
