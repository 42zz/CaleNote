//
//  TopBarView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import SwiftUI

/// トップバービュー
/// 表示切替トグル、月表示、検索、今日フォーカスを配置
struct TopBarView: View {
    // MARK: - Bindings

    /// サイドバー表示フラグ
    @Binding var showSidebar: Bool

    /// 検索画面表示フラグ
    @Binding var showSearch: Bool

    /// 現在のフォーカス日付
    @Binding var focusDate: Date

    /// 今日へスクロールするアクション
    var scrollToToday: () -> Void

    // MARK: - State

    /// 月表示ポップオーバー
    @State private var showMonthPicker = false

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
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Sidebar Toggle Button

    private var sidebarToggleButton: some View {
        Button {
            withAnimation {
                showSidebar.toggle()
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(.primary)
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
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerView(selectedDate: $focusDate)
                .presentationDetents([.medium])
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

// MARK: - Month Picker View

/// 月選択ビュー
struct MonthPickerView: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "月を選択",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("月を選択")
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
}

#Preview {
    TopBarView(
        showSidebar: .constant(false),
        showSearch: .constant(false),
        focusDate: .constant(Date()),
        scrollToToday: {}
    )
}
