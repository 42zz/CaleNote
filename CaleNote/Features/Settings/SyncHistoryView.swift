//
//  SyncHistoryView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import SwiftUI
import SwiftData

/// 同期履歴表示ビュー
struct SyncHistoryView: View {
    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    @State private var syncLogger = SyncLogger.shared
    @State private var selectedLog: SyncLog?
    @State private var showingExportOptions = false
    @State private var exportFileURL: URL?
    @State private var showingClearAlert = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if syncLogger.allLogs.isEmpty {
                    emptyState
                } else {
                    logsSection
                }
            }
            .navigationTitle("Sync History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export Logs", systemImage: "square.and.arrow.up") {
                            exportLogs()
                        }

                        Button("Clear All", systemImage: "trash", role: .destructive) {
                            showingClearAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(syncLogger.allLogs.isEmpty)
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("Clear All Logs", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    syncLogger.clearAllLogs()
                }
            } message: {
                Text("Are you sure you want to delete all sync logs? This action cannot be undone.")
            }
        }
        .onAppear {
            syncLogger.configure(with: modelContext)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sync Logs", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Sync history will appear here after you perform a sync.")
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        ForEach(syncLogger.allLogs) { log in
            Button {
                selectedLog = log
            } label: {
                LogRowView(log: log)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .sheet(item: $selectedLog) { log in
            LogDetailView(log: log)
        }
    }

    // MARK: - Actions

    private func exportLogs() {
        if let url = syncLogger.exportLogs() {
            exportFileURL = url
            showingExportOptions = true
        }
    }
}

// MARK: - Log Row View

struct LogRowView: View {
    let log: SyncLog

    var body: some View {
        HStack(spacing: 12) {
            // ステータスアイコン
            Text(log.statusIcon)
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                // 同期日時
                Text(log.startAtFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // ステータス
                Text(log.isSuccess ? "Success" : "Failed")
                    .font(.headline)
                    .foregroundStyle(log.isSuccess ? .green : .red)

                // サマリー
                Text(log.summaryDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // 所要時間
            if log.endAt != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1fs", log.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Log Detail View

struct LogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let log: SyncLog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ステータスセクション
                    statusSection

                    Divider()

                    // 詳細セクション
                    detailsSection

                    if log.totalProcessedCount > 0 {
                        Divider()
                        entriesSection
                    }

                    if let error = log.errorMessage {
                        Divider()
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Sync Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 12) {
            Text(log.statusIcon)
                .font(.system(size: 40))

            VStack(alignment: .leading, spacing: 4) {
                Text(log.isSuccess ? "Success" : "Failed")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(log.isSuccess ? .green : .red)

                Text(log.startAtFormatted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let end = log.endAt {
                    Text(String(format: "Duration: %.2f seconds", log.duration))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            SyncDetailRow(label: "Direction", value: log.direction.rawValue.capitalized)
            SyncDetailRow(label: "Type", value: log.syncType.capitalized)
            SyncDetailRow(label: "syncToken", value: log.usedSyncToken ? "Used" : "Not used (full sync)")

            if log.apiRequestCount > 0 {
                SyncDetailRow(label: "API Requests", value: "\(log.apiRequestCount)")
            }

            if log.retryCount > 0 {
                SyncDetailRow(label: "Retries", value: "\(log.retryCount)")
            }
        }
    }

    // MARK: - Entries Section

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processed Entries")
                .font(.headline)

            HStack {
                EntryStat(label: "Added", count: log.addedCount, color: .green)
                Spacer()
                EntryStat(label: "Updated", count: log.updatedCount, color: .blue)
                Spacer()
                EntryStat(label: "Deleted", count: log.deletedCount, color: .red)
            }

            Divider()
                .frame(height: 1)

            HStack {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(log.totalProcessedCount)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Error")
                .font(.headline)
                .foregroundStyle(.red)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

// MARK: - Sync Detail Row

struct SyncDetailRow: View {
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
                .fontWeight(.medium)
        }
    }
}

// MARK: - Entry Stat

struct EntryStat: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    SyncHistoryView()
        .modelContainer(for: SyncLog.self, inMemory: true)
}
