//
//  ConflictResolutionView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/22.
//
import SwiftUI
import SwiftData

struct ConflictResolutionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: GoogleAuthService

    let entry: JournalEntry

    @State private var isResolving = false
    @State private var errorMessage: String?

    private let service = ConflictResolutionService()

    var body: some View {
        NavigationStack {
            List {
                // アラートセクション
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("同期の競合")
                                .font(.headline)
                            Text("ローカルとカレンダーの両方が変更されています")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ローカル版
                Section {
                    VersionCard(
                        title: "ローカル版",
                        subtitle: "このデバイスの最新版",
                        entryTitle: entry.title ?? "（タイトルなし）",
                        bodyText: entry.body,
                        updatedAt: entry.updatedAt,
                        eventDate: entry.eventDate,
                        isPreferred: true
                    )

                    Button {
                        resolveConflict(with: .useLocal)
                    } label: {
                        Label("この版を使う", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isResolving)
                    .buttonStyle(.borderedProminent)
                } header: {
                    Text("オプション 1")
                }

                // リモート版
                Section {
                    VersionCard(
                        title: "カレンダー版",
                        subtitle: "Google Calendarの最新版",
                        entryTitle: entry.conflictRemoteTitle ?? "（タイトルなし）",
                        bodyText: entry.conflictRemoteBody ?? "",
                        updatedAt: entry.conflictRemoteUpdatedAt ?? Date(),
                        eventDate: entry.conflictRemoteEventDate ?? entry.eventDate,
                        isPreferred: false
                    )

                    Button {
                        resolveConflict(with: .useRemote)
                    } label: {
                        Label("この版を使う", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isResolving)
                    .buttonStyle(.bordered)
                } header: {
                    Text("オプション 2")
                }

                // エラー表示
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("競合の解決")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isResolving)
                }
            }
        }
    }

    private func resolveConflict(with resolution: ConflictResolutionService.Resolution) {
        Task {
            isResolving = true
            errorMessage = nil

            do {
                let targetCalendarId = JournalWriteSettings.loadWriteCalendarId() ?? "primary"
                try await service.resolveConflict(
                    entry: entry,
                    resolution: resolution,
                    targetCalendarId: targetCalendarId,
                    auth: auth,
                    modelContext: modelContext
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isResolving = false
            }
        }
    }
}

// バージョン比較カード
private struct VersionCard: View {
    let title: String
    let subtitle: String
    let entryTitle: String
    let bodyText: String
    let updatedAt: Date
    let eventDate: Date
    let isPreferred: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPreferred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("タイトル:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entryTitle)
                        .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("本文:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(bodyText)
                        .font(.subheadline)
                        .lineLimit(3)
                }

                HStack {
                    Text("イベント日時:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(eventDate, style: .date)
                        .font(.caption)
                }

                HStack {
                    Text("更新日時:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDateTime(updatedAt))
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
