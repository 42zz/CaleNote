//
//  NavigationSidebarView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import GoogleSignIn
import SwiftUI

/// サイドバービュー
/// Google Calendar アプリの左サイドバーをベンチマークとした構成
struct NavigationSidebarView: View {
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
            .navigationTitle(L10n.tr("app.name"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.tr("common.close"))
                    .accessibilityHint(L10n.tr("sidebar.close.hint"))
                }
            }
        }
    }

    // MARK: - Calendar Toggle Section

    private var calendarToggleSection: some View {
        Section {
            Toggle(isOn: $showGoogleCalendarEvents) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                    Text(L10n.tr("source.google_calendar"))
                }
            }
            .accessibilityValue(showGoogleCalendarEvents ? L10n.tr("common.visible") : L10n.tr("common.hidden"))

            Toggle(isOn: $showCaleNoteEntries) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 12, height: 12)
                    Text(L10n.tr("sidebar.calenote_entries"))
                }
            }
            .accessibilityValue(showCaleNoteEntries ? L10n.tr("common.visible") : L10n.tr("common.hidden"))
        } header: {
            Text(L10n.tr("sidebar.calendar_visibility"))
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        Section {
            NavigationLink {
                SettingsView()
            } label: {
                Label(L10n.tr("common.settings"), systemImage: "gearshape")
            }
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        Section {
            Button {
                openFeedbackURL()
            } label: {
                Label(L10n.tr("feedback.send"), systemImage: "envelope")
            }
            .accessibilityHint(L10n.tr("feedback.email.hint"))

            Button {
                openHelpURL()
            } label: {
                Label(L10n.tr("common.help"), systemImage: "questionmark.circle")
            }
            .accessibilityHint(L10n.tr("help.open.hint"))
        } header: {
            Text(L10n.tr("common.support"))
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
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
                        Text(auth.userName ?? L10n.tr("common.user"))
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
                    Label(L10n.tr("auth.google.sign_in"), systemImage: "person.badge.plus")
                }
            }
        } header: {
            Text(L10n.tr("common.account"))
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
