//
//  MonthCalendarPickerView.swift
//  CaleNote
//
//  Created by Codex on 2025/12/30.
//

import SwiftUI

/// 月カレンダーピッカー
/// グリッド形式の日付表示、今日ハイライト、エントリー存在日のドット表示に対応
struct MonthCalendarPickerView: View {
    // MARK: - Bindings

    @Binding var selectedDate: Date

    // MARK: - Properties

    /// エントリー存在日の集合（startOfDay）
    let entryDates: Set<Date>

    /// 日付選択時のコールバック
    var onSelectDate: ((Date) -> Void)? = nil

    // MARK: - State

    @State private var displayMonth: Date

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    // MARK: - Init

    init(
        selectedDate: Binding<Date>,
        entryDates: Set<Date>,
        onSelectDate: ((Date) -> Void)? = nil
    ) {
        _selectedDate = selectedDate
        self.entryDates = entryDates
        self.onSelectDate = onSelectDate

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate.wrappedValue))
            ?? selectedDate.wrappedValue
        _displayMonth = State(initialValue: monthStart)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                weekdayHeader
                calendarGrid
                footer
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .accessibilityLabel("前月")
            .accessibilityHint("前の月に移動します")

            Spacer(minLength: 0)

            monthSelector

            Spacer(minLength: 0)

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .accessibilityLabel("翌月")
            .accessibilityHint("次の月に移動します")
        }
    }

    private var monthSelector: some View {
        ZStack {
            Text(monthYearString(for: displayMonth))
                .font(.headline)
                .fontWeight(.semibold)

            DatePicker(
                "",
                selection: Binding(
                    get: { displayMonth },
                    set: { newValue in
                        displayMonth = startOfMonth(for: newValue)
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .opacity(0.02)
            .accessibilityLabel("年月を選択")
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let hasEntry = entryDates.contains(calendar.startOfDay(for: date))

        return Button {
            selectedDate = date
            onSelectDate?(date)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                isToday ? Color.accentColor : Color.clear,
                                lineWidth: accessibilityContrast == .increased ? 2 : 1
                            )
                    )
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                if hasEntry {
                    Circle()
                        .fill(isSelected ? Color.white : (accessibilityContrast == .increased ? Color.primary : Color.accentColor))
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(for: date, isToday: isToday, hasEntry: hasEntry))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("日付を選択します")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                let today = Date()
                selectedDate = today
                displayMonth = startOfMonth(for: today)
                onSelectDate?(today)
                dismiss()
            } label: {
                Text("今日")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(accessibilityContrast == .increased ? 0.2 : 0.1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        guard let symbols = formatter.shortWeekdaySymbols, !symbols.isEmpty else {
            return []
        }
        let calendar = Calendar.current
        let startIndex = max(calendar.firstWeekday - 1, 0)
        if startIndex >= symbols.count {
            return symbols
        }
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        let monthStart = startOfMonth(for: displayMonth)
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var dates: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                dates.append(date)
            }
        }

        while dates.count % 7 != 0 {
            dates.append(nil)
        }

        return dates
    }

    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func changeMonth(by offset: Int) {
        let calendar = Calendar.current
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: displayMonth) else {
            return
        }
        displayMonth = startOfMonth(for: newMonth)
    }

    private func dayAccessibilityLabel(for date: Date, isToday: Bool, hasEntry: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        var parts = [formatter.string(from: date)]
        if isToday {
            parts.append("今日")
        }
        if hasEntry {
            parts.append("エントリーあり")
        }
        return parts.joined(separator: "、")
    }
}

#Preview {
    MonthCalendarPickerView(
        selectedDate: .constant(Date()),
        entryDates: []
    )
}
