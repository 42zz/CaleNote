//
//  ErrorHandler.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation
import Combine
import OSLog

/// エラーハンドリングを担当するサービス
@MainActor
final class ErrorHandler: ObservableObject {
    // MARK: - Singleton

    static let shared = ErrorHandler()

    // MARK: - Published Properties

    /// 現在のエラーメッセージ（UI表示用）
    @Published var currentError: CaleNoteError?

    /// エラー表示フラグ
    @Published var showError = false

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "ErrorHandler")

    // MARK: - Initialization

    private init() {}

    // MARK: - Error Handling

    /// エラーを処理する
    /// - Parameters:
    ///   - error: 処理するエラー
    ///   - context: エラーのコンテキスト情報
    ///   - showToUser: ユーザーにエラーを表示するかどうか
    func handle(
        _ error: Error,
        context: String? = nil,
        showToUser: Bool = true
    ) {
        let caleNoteError = convertToCaleNoteError(error)

        // ログに記録
        logError(caleNoteError, context: context)

        // ユーザーに表示
        if showToUser {
            currentError = caleNoteError
            showError = true
        }
    }

    /// エラーを CaleNoteError に変換
    /// - Parameter error: 変換するエラー
    /// - Returns: CaleNoteError
    private func convertToCaleNoteError(_ error: Error) -> CaleNoteError {
        if let caleNoteError = error as? CaleNoteError {
            return caleNoteError
        }

        // URLError を NetworkError に変換
        if let urlError = error as? URLError {
            return .networkError(convertURLError(urlError))
        }

        // その他のエラー
        return .unknown(error)
    }

    /// URLError を NetworkError に変換
    /// - Parameter urlError: URLError
    /// - Returns: NetworkError
    private func convertURLError(_ urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .networkConnectionLost:
            return .connectionFailed
        case .cannotFindHost:
            return .dnsError
        case .notConnectedToInternet:
            return .noConnection
        default:
            return .other(urlError)
        }
    }

    /// エラーをログに記録
    /// - Parameters:
    ///   - error: 記録するエラー
    ///   - context: コンテキスト情報
    private func logError(_ error: CaleNoteError, context: String?) {
        let contextInfo = context.map { " [\($0)]" } ?? ""
        let message = "\(contextInfo) \(error.localizedDescription)"

        switch error {
        case .networkError:
            logger.warning("Network error:\(message, privacy: .public)")
        case .apiError:
            logger.error("API error:\(message, privacy: .public)")
        case .localDataError:
            logger.error("Local data error:\(message, privacy: .public)")
        case .syncError:
            logger.warning("Sync error:\(message, privacy: .public)")
        case .unknown:
            logger.fault("Unknown error:\(message, privacy: .public)")
        }
    }

    /// エラー表示をクリア
    func clearError() {
        currentError = nil
        showError = false
    }
}

// MARK: - Convenience Methods

extension ErrorHandler {
    /// ネットワークエラーを処理
    func handleNetworkError(_ error: NetworkError, context: String? = nil) {
        handle(CaleNoteError.networkError(error), context: context)
    }

    /// API エラーを処理
    func handleAPIError(_ error: APIError, context: String? = nil) {
        handle(CaleNoteError.apiError(error), context: context)
    }

    /// ローカルデータエラーを処理
    func handleLocalDataError(_ error: LocalDataError, context: String? = nil) {
        handle(CaleNoteError.localDataError(error), context: context)
    }

    /// 同期エラーを処理
    func handleSyncError(_ message: String, context: String? = nil) {
        handle(CaleNoteError.syncError(message), context: context)
    }
}
