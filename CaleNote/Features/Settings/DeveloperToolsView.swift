//
//  DeveloperToolsView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/22.
//
import SwiftUI
import SwiftData

struct DeveloperToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SyncLog.timestamp, order: .reverse) private var logs: [SyncLog]

    @State private var selectedLog: SyncLog?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section("同期ログ") {
                if logs.isEmpty {
                    Text("ログがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        Button {
                            selectedLog = log
                        } label: {
                            LogRowView(log: log)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section("操作") {
                Button("直近100件をコピー（JSON）") {
                    copyRecentLogs(count: 100)
                }
                .disabled(logs.isEmpty)

                Button("ログを全削除", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(logs.isEmpty)
            }

            Section("統計") {
                HStack {
                    Text("ログ総数")
                    Spacer()
                    Text("\(logs.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("開発者向けツール")
        .sheet(item: $selectedLog) { log in
            LogDetailView(log: log)
        }
        .confirmationDialog(
            "全てのログを削除しますか？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                deleteAllLogs()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func copyRecentLogs(count: Int) {
        let recentLogs = Array(logs.prefix(count))
        let jsonArray = recentLogs.map { $0.toJSON() }

        if let data = try? JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = jsonString
        }
    }

    private func deleteAllLogs() {
        for log in logs {
            modelContext.delete(log)
        }
        try? modelContext.save()
    }
}

private struct LogRowView: View {
    let log: SyncLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.syncType)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(formatTimestamp(log.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if log.errorType != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if let calendarHash = log.calendarIdHash {
                    Text("📅 \(calendarHash)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if log.had410Fallback {
                    Text("410↻")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if log.had429Retry {
                    Text("429⏱")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Spacer()

                Text("↑\(log.updatedCount) ↓\(log.deletedCount) ⊘\(log.skippedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

private struct LogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let log: SyncLog

    var body: some View {
        NavigationStack {
            List {
                Section("基本情報") {
                    DetailRow(label: "同期種別", value: log.syncType)
                    DetailRow(label: "開始時刻", value: formatFullTimestamp(log.timestamp))
                    if let endTime = log.endTimestamp {
                        DetailRow(label: "終了時刻", value: formatFullTimestamp(endTime))
                        DetailRow(label: "所要時間", value: formatDuration(log.timestamp, endTime))
                    }
                    if let calendarHash = log.calendarIdHash {
                        DetailRow(label: "カレンダーID (hash)", value: calendarHash)
                    }
                }

                Section("結果") {
                    DetailRow(label: "更新", value: "\(log.updatedCount)")
                    DetailRow(label: "削除", value: "\(log.deletedCount)")
                    DetailRow(label: "スキップ", value: "\(log.skippedCount)")
                    DetailRow(label: "競合", value: "\(log.conflictCount)")

                    if let httpCode = log.httpStatusCode {
                        DetailRow(label: "HTTPステータス", value: "\(httpCode)")
                    }
                }

                Section("フラグ") {
                    DetailRow(label: "410フォールバック", value: log.had410Fallback ? "あり" : "なし")
                    DetailRow(label: "429リトライ", value: log.had429Retry ? "あり" : "なし")
                }

                if log.errorType != nil || log.errorMessage != nil {
                    Section("エラー") {
                        if let errorType = log.errorType {
                            DetailRow(label: "エラー種別", value: errorType)
                        }
                        if let errorMsg = log.errorMessage {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("エラーメッセージ")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(errorMsg)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("操作") {
                    Button("このログをコピー（JSON）") {
                        copyLogAsJSON()
                    }
                }
            }
            .navigationTitle("ログ詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatDuration(_ start: Date, _ end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        if duration < 60 {
            return String(format: "%.1f秒", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)分\(seconds)秒"
        }
    }

    private func copyLogAsJSON() {
        let json = log.toJSON()
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = jsonString
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}
