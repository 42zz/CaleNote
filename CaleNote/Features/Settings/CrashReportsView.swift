//
//  CrashReportsView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import SwiftUI
import OSLog

/// クラッシュレポートとエラーログを表示・管理するビュー
struct CrashReportsView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @StateObject private var crashReporting = CrashReportingService.shared

    @State private var selectedTab: CrashTab = .crashes
    @State private var showingExportSheet = false
    @State private var showingClearAlert = false
    @State private var exportedText: String?

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "CrashReportsView")

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("", selection: $selectedTab) {
                    Text("クラッシュ (\(crashReporting.crashReports.count))")
                        .tag(CrashTab.crashes)
                    Text("エラーログ (\(crashReporting.errorLogs.count))")
                        .tag(CrashTab.errors)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if selectedTab == .crashes {
                            crashesContent
                        } else {
                            errorLogsContent
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("クラッシュレポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if selectedTab == .errors {
                            Button("エクスポート") {
                                exportErrorLogs()
                            }
                        }

                        Button("クリア") {
                            showingClearAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("クリア確認", isPresented: $showingClearAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("クリア", role: .destructive) {
                    clearCurrentData()
                }
            } message: {
                Text(selectedTab == .crashes ? "すべてのクラッシュレポートをクリアしますか？" : "すべてのエラーログをクリアしますか？")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let text = exportedText {
                    ExportSheet(text: text, filename: exportFilename)
                }
            }
        }
    }

    // MARK: - Crash Reports Content

    @ViewBuilder
    private var crashesContent: some View {
        if crashReporting.crashReports.isEmpty {
            emptyState(
                icon: "checkmark.shield.fill",
                title: "クラッシュはありません",
                message: "アプリは安定して動作しています"
            )
        } else {
            // Summary
            crashSummaryCard

            // Reports
            ForEach(crashReporting.crashReports) { report in
                CrashReportCard(report: report)
            }
        }
    }

    /// クラッシュサマリーカード
    private var crashSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("クラッシュサマリー")
                    .font(.headline)
            }

            Divider()

            HStack {
                VStack(alignment: .leading) {
                    Text("総クラッシュ数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(crashReporting.totalCrashCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                if let lastDate = crashReporting.lastCrashDate {
                    VStack(alignment: .trailing) {
                        Text("最後のクラッシュ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastDate, style: .relative)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Error Logs Content

    @ViewBuilder
    private var errorLogsContent: some View {
        if crashReporting.errorLogs.isEmpty {
            emptyState(
                icon: "checkmark.circle.fill",
                title: "エラーログはありません",
                message: "エラーは記録されていません"
            )
        } else {
            // Filter controls could be added here
            ForEach(crashReporting.errorLogs.prefix(100)) { log in
                ErrorLogCard(log: log)
            }

            if crashReporting.errorLogs.count > 100 {
                Text("最近100件を表示中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Actions

    /// エラーログをエクスポート
    private func exportErrorLogs() {
        exportedText = crashReporting.exportErrorLogs()
        showingExportSheet = true
    }

    /// 現在のデータをクリア
    private func clearCurrentData() {
        if selectedTab == .crashes {
            crashReporting.clearAllCrashReports()
            logger.info("Cleared all crash reports")
        } else {
            crashReporting.clearErrorLogs()
            logger.info("Cleared all error logs")
        }
    }

    /// エクスポートファイル名
    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let date = formatter.string(from: Date())
        return "CaleNote_ErrorLogs_\(date).md"
    }
}

// MARK: - Crash Tab

enum CrashTab {
    case crashes
    case errors
}

// MARK: - Crash Report Card

struct CrashReportCard: View {
    let report: CrashReport
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.exceptionName)
                        .font(.headline)

                    Text(report.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider()

                // Details
                VStack(alignment: .leading, spacing: 8) {
                    if let reason = report.exceptionReason {
                        DetailRow(title: "理由", value: reason)
                    }

                    DetailRow(title: "バージョン", value: "\(report.appVersion) (\(report.buildNumber))")
                    DetailRow(title: "デバイス", value: report.deviceModel)
                    DetailRow(title: "OS", value: report.osVersion)

                    if !report.stackTrace.isEmpty {
                        Text("スタックトレース")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        Text(report.stackTrace.prefix(10).joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Error Log Card

struct ErrorLogCard: View {
    let log: ErrorLog
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                severityIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(log.errorDescription)
                        .font(.subheadline)
                        .lineLimit(isExpanded ? nil : 2)

                    Text(log.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    if let context = log.context {
                        DetailRow(title: "コンテキスト", value: context)
                    }
                    DetailRow(title: "タイプ", value: log.errorType)
                    DetailRow(title: "重大度", value: log.severity.rawValue)
                }
            }
        }
        .cardStyle()
    }

    private var severityIcon: some View {
        Image(systemName: iconName)
            .foregroundColor(iconColor)
    }

    private var iconName: String {
        switch log.severity {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        case .critical:
            return "flame.fill"
        }
    }

    private var iconColor: Color {
        switch log.severity {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        case .critical:
            return .purple
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    let text: String
    let filename: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("エクスポートプレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("共有") {
                        shareText()
                    }
                }
            }
        }
    }

    private func shareText() {
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Card Style Modifier

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}

// MARK: - Preview

#Preview("クラッシュあり") {
    CrashReportsView()
}

#Preview("クラッシュなし") {
    CrashReportsView()
}
