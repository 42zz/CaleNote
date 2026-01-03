//
//  CrashReportingService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import Foundation
import Combine
import OSLog
import UIKit

/// クラッシュレポートとエラートラッキングを管理するサービス
@MainActor
final class CrashReportingService: ObservableObject {
    // MARK: - Singleton

    static let shared = CrashReportingService()

    // MARK: - Published Properties

    /// 保存されているクラッシュレポート
    @Published var crashReports: [CrashReport] = []

    /// 総クラッシュ数
    @Published var totalCrashCount: Int = 0

    /// 最後のクラッシュ日時
    @Published var lastCrashDate: Date?

    /// エラーログ
    @Published var errorLogs: [ErrorLog] = []

    // MARK: - Private Properties

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "CrashReporting")
    private let crashReportsFile = "crash_reports.json"
    private let errorLogsFile = "error_logs.json"

    // MARK: - Initialization

    private init() {
        setupCrashHandler()
        setupSignalHandlers()
        loadCrashReports()
        loadErrorLogs()
        checkForPreviousCrash()
    }

    // MARK: - Setup

    /// クラッシュハンドラーを設定
    private func setupCrashHandler() {
        //NSSetUncaughtExceptionHandler は iOS 15.0+ 非推奨だが、まだ使用可能
        //将来的には Task Diagnostics API へ移行
        NSSetUncaughtExceptionHandler { exception in
            Task { @MainActor in
                await CrashReportingService.shared.handleUncaughtException(exception)
            }
        }

        logger.info("Crash handler installed")
    }

    /// シグナルハンドラーを設定
    /// Note: Swift 6 での信号ハンドリングは複雑なため、
    /// 現在は未捕捉例外ハンドラーのみ実装
    private func setupSignalHandlers() {
        // 将来的に Swift 6 非同期対応の信号ハンドリングを実装
        logger.info("Signal handlers skipped (will use Task Diagnostics API in future)")
    }

    // MARK: - Crash Handling

    /// 未捕捉例外を処理
    func handleUncaughtException(_ exception: NSException) async {
        logger.error("Uncaught exception: \(exception.name.rawValue, privacy: .public)")

        // スタックトレースを収集
        let stackTrace = Thread.callStackSymbols

        // デバイス情報を収集
        let deviceInfo = collectDeviceInfo()

        // 附加情報を収集
        var additionalInfo: [String: String] = [:]
        additionalInfo["signal"] = exception.name.rawValue
        // Note: Thread.current cannot be used from async contexts, skipping thread info

        // クラッシュレポートを作成
        let report = CrashReport(
            id: UUID(),
            date: Date(),
            exceptionName: exception.name.rawValue,
            exceptionReason: exception.reason,
            stackTrace: stackTrace,
            appVersion: deviceInfo["appVersion"] ?? "Unknown",
            buildNumber: deviceInfo["buildNumber"] ?? "Unknown",
            deviceModel: deviceInfo["deviceModel"] ?? "Unknown",
            osVersion: deviceInfo["osVersion"] ?? "Unknown",
            additionalInfo: additionalInfo
        )

        // レポートを保存
        await saveCrashReport(report)

        // ログに記録
        logger.fault("""
        Crash occurred:
        - Exception: \(exception.name.rawValue)
        - Reason: \(exception.reason ?? "No reason")
        - Stack trace: \(stackTrace.prefix(5).joined(separator: "\n"))
        """)
    }

    /// 前回のクラッシュをチェック
    private func checkForPreviousCrash() {
        // アプリ起動時に前回のクラッシュを検出
        // 実装は簡略化（実際には起動フラグなどを使用）
        let lastLaunchDate = UserDefaults.standard.object(forKey: "lastLaunchDate") as? Date
        let currentLaunchDate = Date()

        if let last = lastLaunchDate {
            let timeSinceLastLaunch = currentLaunchDate.timeIntervalSince(last)
            // 前回の起動から24時間以内なら正常終了とみなす
            if timeSinceLastLaunch < 86400 {
                // 正常終了
                logger.debug("App terminated normally")
            }
        }

        UserDefaults.standard.set(currentLaunchDate, forKey: "lastLaunchDate")
    }

    // MARK: - Error Logging

    /// エラーをログに記録
    func logError(
        _ error: Error,
        context: String? = nil,
        severity: ErrorSeverity = .error
    ) {
        let log = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: error.localizedDescription,
            context: context,
            severity: severity,
            errorType: String(describing: type(of: error))
        )

        errorLogs.insert(log, at: 0)

        // ログを保持する数を制限（最新1000件）
        if errorLogs.count > 1000 {
            errorLogs = Array(errorLogs.prefix(1000))
        }

        // 保存
        saveErrorLogs()

        // Logger にも出力
        switch severity {
        case .info:
            logger.info("Error logged: \(error.localizedDescription, privacy: .private)")
        case .warning:
            logger.warning("Error logged: \(error.localizedDescription, privacy: .private)")
        case .error:
            logger.error("Error logged: \(error.localizedDescription, privacy: .private)")
        case .critical:
            logger.critical("Error logged: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Data Management

    /// クラッシュレポートを保存
    private func saveCrashReport(_ report: CrashReport) async {
        crashReports.insert(report, at: 0)
        totalCrashCount += 1
        lastCrashDate = report.date

        // ファイルに保存
        if let url = crashReportsFileURL {
            do {
                let data = try JSONEncoder().encode(crashReports)
                try data.write(to: url)
                logger.info("Crash report saved: \(report.id.uuidString, privacy: .private)")
            } catch {
                logger.error("Failed to save crash report: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// クラッシュレポートを読み込み
    private func loadCrashReports() {
        guard let url = crashReportsFileURL,
              let data = try? Data(contentsOf: url) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            crashReports = try decoder.decode([CrashReport].self, from: data)
            totalCrashCount = crashReports.count
            lastCrashDate = crashReports.first?.date
            logger.info("Loaded \(self.crashReports.count) crash reports")
        } catch {
            logger.error("Failed to load crash reports: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// エラーログを保存
    private func saveErrorLogs() {
        guard let url = errorLogsFileURL else { return }

        do {
            let data = try JSONEncoder().encode(errorLogs)
            try data.write(to: url)
        } catch {
            logger.error("Failed to save error logs: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// エラーログを読み込み
    private func loadErrorLogs() {
        guard let url = errorLogsFileURL,
              let data = try? Data(contentsOf: url) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            errorLogs = try decoder.decode([ErrorLog].self, from: data)
            logger.info("Loaded \(self.errorLogs.count) error logs")
        } catch {
            logger.error("Failed to load error logs: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Public API

    /// クラッシュレポートを削除
    func deleteCrashReport(_ report: CrashReport) {
        crashReports.removeAll { $0.id == report.id }
        saveCrashReportsSync()
    }

    /// すべてのクラッシュレポートを削除
    func clearAllCrashReports() {
        crashReports.removeAll()
        totalCrashCount = 0
        lastCrashDate = nil
        saveCrashReportsSync()

        // ファイルを削除
        if let url = crashReportsFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// エラーログを削除
    func clearErrorLogs() {
        errorLogs.removeAll()
        saveErrorLogs()

        // ファイルを削除
        if let url = errorLogsFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// エラーログをエクスポート
    func exportErrorLogs() -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")

        var content = "# Error Logs\n\n"
        content += "**エクスポート日時**: \(formatter.string(from: Date()))\n\n"
        content += "**総件数**: \(errorLogs.count)\n\n"

        for log in errorLogs {
            content += "## \(log.formattedDate) - \(log.severity.rawValue)\n"
            content += "**タイプ**: \(log.errorType)\n"
            if let context = log.context {
                content += "**コンテキスト**: \(context)\n"
            }
            content += "**説明**: \(log.errorDescription)\n\n"
        }

        return content
    }

    // MARK: - Helper Methods

    /// クラッシュレポートを同期的に保存
    private func saveCrashReportsSync() {
        guard let url = crashReportsFileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(crashReports)
            try data.write(to: url)
        } catch {
            logger.error("Failed to save crash reports: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// デバイス情報を収集
    private func collectDeviceInfo() -> [String: String] {
        var info: [String: String] = [:]

        info["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        info["buildNumber"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        info["deviceModel"] = UIDevice.current.model
        info["osVersion"] = UIDevice.current.systemVersion
        info["locale"] = Locale.current.identifier
        info["timezone"] = TimeZone.current.identifier

        return info
    }

    /// クラッシュレポートファイルの URL
    private var crashReportsFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(crashReportsFile)
    }

    /// エラーログファイルの URL
    private var errorLogsFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(errorLogsFile)
    }
}

// MARK: - Supporting Types

/// エラーログ
struct ErrorLog: Codable, Identifiable {
    let id: UUID
    let date: Date
    let errorDescription: String
    let context: String?
    let severity: ErrorSeverity
    let errorType: String

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

/// エラーの重大度
enum ErrorSeverity: String, Codable {
    case info
    case warning
    case error
    case critical
}
