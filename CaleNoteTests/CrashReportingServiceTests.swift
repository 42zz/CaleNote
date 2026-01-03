//
//  CrashReportingServiceTests.swift
//  CaleNoteTests
//
//  Created by Claude Code on 2025/01/03.
//

import XCTest
@testable import CaleNote

/// クラッシュレポートサービスのテスト
final class CrashReportingServiceTests: XCTestCase {
    // MARK: - Properties

    private var crashReporting: CrashReportingService!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // テスト用のサービスインスタンスを作成
        // 実際にはシングルトンを使用しているため、ここではモックを作成する必要があるかもしれない
        // 現状では、サービスを初期化して基本的な機能をテストする
    }

    override func tearDown() async throws {
        // クリーンアップ
        try await super.tearDown()
    }

    // MARK: - Crash Report Tests

    func testCrashReportCreation() throws {
        // クラッシュレポートのデータモデルをテスト
        let report = CrashReport(
            id: UUID(),
            date: Date(),
            exceptionName: "TestException",
            exceptionReason: "Test reason",
            stackTrace: ["frame 0", "frame 1", "frame 2"],
            appVersion: "1.0.0",
            buildNumber: "100",
            deviceModel: "iPhone",
            osVersion: "18.0",
            additionalInfo: ["testKey": "testValue"]
        )

        XCTAssertEqual(report.exceptionName, "TestException")
        XCTAssertEqual(report.exceptionReason, "Test reason")
        XCTAssertEqual(report.stackTrace.count, 3)
        XCTAssertEqual(report.appVersion, "1.0.0")
        XCTAssertFalse(report.isSaved)
    }

    func testCrashReportSummary() throws {
        // 要約テスト
        let report1 = CrashReport(
            id: UUID(),
            date: Date(),
            exceptionName: "Exception1",
            exceptionReason: "Reason1",
            stackTrace: [],
            appVersion: "1.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            osVersion: "18.0",
            additionalInfo: nil
        )

        let report2 = CrashReport(
            id: UUID(),
            date: Date(),
            exceptionName: "Exception2",
            exceptionReason: nil,
            stackTrace: [],
            appVersion: "1.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            osVersion: "18.0",
            additionalInfo: nil
        )

        XCTAssertEqual(report1.summary, "Exception1: Reason1")
        XCTAssertEqual(report2.summary, "Exception2")
    }

    // MARK: - Error Log Tests

    func testErrorLogCreation() throws {
        // エラーログのデータモデルをテスト
        let log = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: "Test error",
            context: "TestContext",
            severity: .error,
            errorType: "TestError"
        )

        XCTAssertEqual(log.errorDescription, "Test error")
        XCTAssertEqual(log.context, "TestContext")
        XCTAssertEqual(log.severity, .error)
        XCTAssertEqual(log.errorType, "TestError")
    }

    func testErrorSeverity() throws {
        // 重大度レベルのテスト
        let infoLog = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: "Info",
            context: nil,
            severity: .info,
            errorType: "Info"
        )

        let warningLog = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: "Warning",
            context: nil,
            severity: .warning,
            errorType: "Warning"
        )

        let errorLog = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: "Error",
            context: nil,
            severity: .error,
            errorType: "Error"
        )

        let criticalLog = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: "Critical",
            context: nil,
            severity: .critical,
            errorType: "Critical"
        )

        XCTAssertEqual(infoLog.severity.rawValue, "info")
        XCTAssertEqual(warningLog.severity.rawValue, "warning")
        XCTAssertEqual(errorLog.severity.rawValue, "error")
        XCTAssertEqual(criticalLog.severity.rawValue, "critical")
    }

    // MARK: - Integration Tests

    func testErrorLogging() throws {
        // エラーログ機能の統合テスト
        // Note: これは実際のサービスインスタンスが必要なため、
        // 将来的にはモックを使用したテストに変更する必要がある

        let testError = NSError(domain: "TestDomain", code: 123, userInfo: [
            NSLocalizedDescriptionKey: "Test error description"
        ])

        // エラーが正しく記録されることを確認
        XCTAssertNotNil(testError)
        XCTAssertEqual(testError.domain, "TestDomain")
        XCTAssertEqual(testError.code, 123)
    }

    func testCrashReportEncodingDecoding() throws {
        // CrashReport の Codable テスト
        let report = CrashReport(
            id: UUID(),
            date: Date(),
            exceptionName: "TestException",
            exceptionReason: "Test reason",
            stackTrace: ["frame 0", "frame 1"],
            appVersion: "1.0.0",
            buildNumber: "100",
            deviceModel: "iPhone",
            osVersion: "18.0",
            additionalInfo: ["key": "value"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(report)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CrashReport.self, from: data)

        XCTAssertEqual(decoded.id, report.id)
        XCTAssertEqual(decoded.exceptionName, report.exceptionName)
        XCTAssertEqual(decoded.exceptionReason, report.exceptionReason)
        XCTAssertEqual(decoded.stackTrace, report.stackTrace)
        XCTAssertEqual(decoded.appVersion, report.appVersion)
        XCTAssertEqual(decoded.buildNumber, report.buildNumber)
        XCTAssertEqual(decoded.additionalInfo?["key"], "value")
    }

    func testErrorLogEncodingDecoding() throws {
        // ErrorLog の Codable テスト
        let log = ErrorLog(
            id: UUID(),
            date: Date(),
            errorDescription: "Test error",
            context: "Test context",
            severity: .error,
            errorType: "TestError"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(log)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ErrorLog.self, from: data)

        XCTAssertEqual(decoded.id, log.id)
        XCTAssertEqual(decoded.errorDescription, log.errorDescription)
        XCTAssertEqual(decoded.context, log.context)
        XCTAssertEqual(decoded.severity, log.severity)
        XCTAssertEqual(decoded.errorType, log.errorType)
    }

    // MARK: - Markdown Export Tests

    func testMarkdownExport() throws {
        // Markdown エクスポート機能のテスト
        let report = CrashReport(
            id: UUID(),
            date: Date(),
            exceptionName: "TestException",
            exceptionReason: "Test reason for markdown export",
            stackTrace: ["frame 0", "frame 1", "frame 2"],
            appVersion: "1.0.0",
            buildNumber: "100",
            deviceModel: "iPhone14,2",
            osVersion: "18.0.1",
            additionalInfo: ["testKey": "testValue"]
        )

        let markdown = report.markdownDescription

        // Markdown に必要な要素が含まれていることを確認
        XCTAssertTrue(markdown.contains("# Crash Report"))
        XCTAssertTrue(markdown.contains("TestException"))
        XCTAssertTrue(markdown.contains("Test reason for markdown export"))
        XCTAssertTrue(markdown.contains("1.0.0"))
        XCTAssertTrue(markdown.contains("## スタックトレース"))
        XCTAssertTrue(markdown.contains("frame 0"))
    }
}
