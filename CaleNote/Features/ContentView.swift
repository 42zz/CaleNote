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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    /// オンボーディング完了フラグ
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// サイドバー表示状態
    @State private var showSidebar = false

    /// 設定画面表示状態
    @State private var showSettings = false

    /// オンボーディング表示状態
    @State private var showOnboarding = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            // メインコンテンツ（タイムライン）
            TimelineView(
                showSidebarButton: true,
                onSidebarButtonTap: {
                    AccessibilityAnimation.perform(.easeInOut(duration: 0.25), reduceMotion: reduceMotion) {
                        showSidebar.toggle()
                    }
                }
            )
            .disabled(showSidebar)

            // サイドバーオーバーレイ
            if showSidebar {
                Button {
                    AccessibilityAnimation.perform(.easeInOut(duration: 0.25), reduceMotion: reduceMotion) {
                        showSidebar = false
                    }
                } label: {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("サイドバーを閉じる")
                .accessibilityHint("メイン画面に戻ります")

                SidebarView(showSettings: $showSettings)
                    .transition(reduceMotion ? .identity : .move(edge: .leading))
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .task {
            // 初回起動時にカレンダーリストを読み込み
            await calendarListService.loadLocalCalendars()

            // カレンダーリストが空の場合は同期
            if calendarListService.calendars.isEmpty {
                await calendarListService.syncCalendarList()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, newValue in
            if newValue {
                showOnboarding = false
            }
        }
    }
}
