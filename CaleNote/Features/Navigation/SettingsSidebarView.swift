//
//  SettingsSidebarView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import GoogleSignIn
import SwiftUI

/// 設定サイドバービュー
/// Google Calendar アプリの左サイドバーをベンチマークとした構成
struct SettingsSidebarView: View {
    // MARK: - Environment

    @EnvironmentObject private var auth: GoogleAuthService
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// カレンダー表示切替
    @AppStorage("showGoogleCalendarEvents") private var showGoogleCalendarEvents = true
    @AppStorage("showCaleNoteEntries") private var showCaleNoteEntries = true

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // カレンダー表示切替セクション
                calendarToggleSection

                // 設定リンクセクション
                settingsSection

                // フィードバック導線セクション
                feedbackSection

                // アカウント情報セクション
                accountSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("CaleNote")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("閉じる")
                    .accessibilityHint("サイドバーを閉じます")
                }
            }
        }
    }

    // MARK: - Calendar Toggle Section

    private var calendarToggleSection: some View {
        Section("表示するカレンダー") {
            Toggle(isOn: $showGoogleCalendarEvents) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                    Text("Google Calendar")
                }
            }
            .accessibilityValue(showGoogleCalendarEvents ? "表示中" : "非表示")

            Toggle(isOn: $showCaleNoteEntries) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 12, height: 12)
                    Text("CaleNote エントリー")
                }
            }
            .accessibilityValue(showCaleNoteEntries ? "表示中" : "非表示")
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        Section {
            NavigationLink {
                SettingsView()
            } label: {
                Label("設定", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        Section("サポート") {
            Button {
                openFeedbackURL()
            } label: {
                Label("フィードバックを送信", systemImage: "envelope")
            }
            .accessibilityHint("メールでフィードバックを送信します")

            Button {
                openHelpURL()
            } label: {
                Label("ヘルプ", systemImage: "questionmark.circle")
            }
            .accessibilityHint("ヘルプページを開きます")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section("アカウント") {
            if auth.isAuthenticated {
                HStack(spacing: 12) {
                    // プロフィール画像
                    if let profileURL = auth.userImageURL {
                        AsyncImage(url: profileURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.userName ?? "ユーザー")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(auth.userEmail ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    Task {
                        try? await auth.signIn()
                    }
                } label: {
                    Label("Googleでサインイン", systemImage: "person.badge.plus")
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func openFeedbackURL() {
        guard let url = URL(string: "mailto:feedback@calenote.app") else { return }
        UIApplication.shared.open(url)
    }

    private func openHelpURL() {
        guard let url = URL(string: "https://calenote.app/help") else { return }
        UIApplication.shared.open(url)
    }
}

// Preview disabled due to complex dependency injection requirements
