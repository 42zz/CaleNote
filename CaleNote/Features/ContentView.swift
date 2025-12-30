//
//  ContentView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import SwiftUI

/// メインコンテンツビュー
///
/// サイドバーとタイムラインを組み合わせたメイン画面。
struct ContentView: View {
    // MARK: - Environment

    @EnvironmentObject private var calendarListService: CalendarListService

    // MARK: - State

    /// サイドバー表示状態
    @State private var showSidebar = false

    /// 設定画面表示状態
    @State private var showSettings = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            // メインコンテンツ（タイムライン）
            TimelineView(
                showSidebarButton: true,
                onSidebarButtonTap: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar.toggle()
                    }
                }
            )
            .disabled(showSidebar)

            // サイドバーオーバーレイ
            if showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSidebar = false
                        }
                    }

                SidebarView(showSettings: $showSettings)
                    .transition(.move(edge: .leading))
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .task {
            // 初回起動時にカレンダーリストを読み込み
            await calendarListService.loadLocalCalendars()

            // カレンダーリストが空の場合は同期
            if calendarListService.calendars.isEmpty {
                await calendarListService.syncCalendarList()
            }
        }
    }
}
