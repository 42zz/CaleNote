//
//  TopBarView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

/// トップバービュー
/// 表示切替トグル、月表示、検索、今日フォーカスを配置
struct TopBarView: View {
    // MARK: - Properties

    /// サイドバー表示ボタンを表示するか
    var showsSidebarButton: Bool = true

    /// サイドバー表示アクション
    var onSidebarTap: (() -> Void)?

    /// 検索画面表示フラグ
    @Binding var showSearch: Bool

    /// 現在のフォーカス日付
    @Binding var focusDate: Date

    /// 今日へスクロールするアクション
    var scrollToToday: () -> Void

    /// エントリー存在日の集合（startOfDay）
    var entryDates: Set<Date> = []

    /// 日付選択時のアクション
    var onSelectDate: ((Date) -> Void)? = nil

    // MARK: - State

    /// 月表示ポップオーバー
    @State private var showMonthPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {
            // サイドバートグルボタン
            sidebarToggleButton

            // 月表示
            monthDisplayButton

            Spacer()

            // 検索ボタン
            searchButton

            // 今日フォーカスボタン
            todayFocusButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.cnSurface)
    }

    // MARK: - Sidebar Toggle Button

    private var sidebarToggleButton: some View {
        Group {
            if showsSidebarButton {
                Button {
                    AccessibilityAnimation.perform(reduceMotion: reduceMotion) {
                        onSidebarTap?()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("サイドバーを開く")
                .accessibilityHint("カレンダー一覧を表示します")
                .accessibilityIdentifier("sidebarToggleButton")
            } else {
                Color.clear
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Month Display Button

    private var monthDisplayButton: some View {
        Button {
            showMonthPicker = true
        } label: {
            HStack(spacing: 4) {
                Text(monthYearString)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("月を選択")
        .accessibilityValue(monthYearString)
        .accessibilityHint("月表示のカレンダーを開きます")
        .accessibilityIdentifier("monthDisplayButton")
        .sheet(isPresented: $showMonthPicker) {
            MonthCalendarPickerView(
                selectedDate: $focusDate,
                entryDates: entryDates,
                onSelectDate: onSelectDate
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Search Button

    private var searchButton: some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("検索")
        .accessibilityHint("エントリーを検索します")
        .accessibilityIdentifier("searchButton")
    }

    // MARK: - Today Focus Button

    private var todayFocusButton: some View {
        Button {
            scrollToToday()
        } label: {
            Image(systemName: "calendar.circle")
                .font(.title3)
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("今日へ移動")
        .accessibilityValue(isToday ? "今日を表示中" : "")
        .accessibilityHint("今日の日付にスクロールします")
        .accessibilityIdentifier("todayFocusButton")
    }

    // MARK: - Computed Properties

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: focusDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(focusDate)
    }
}

#Preview {
    TopBarView(
        showsSidebarButton: true,
        onSidebarTap: {},
        showSearch: .constant(false),
        focusDate: .constant(Date()),
        scrollToToday: {},
        entryDates: [],
        onSelectDate: nil
    )
}
