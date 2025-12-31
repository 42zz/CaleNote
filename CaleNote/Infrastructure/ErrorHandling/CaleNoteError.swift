//
//  CaleNoteError.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation

/// CaleNote アプリケーション全体で使用するエラー型
enum CaleNoteError: Error {
    // MARK: - Network Errors
    case networkError(NetworkError)

    // MARK: - API Errors
    case apiError(APIError)

    // MARK: - Local Data Errors
    case localDataError(LocalDataError)

    // MARK: - Sync Errors
    case syncError(String)

    // MARK: - Unknown Error
    case unknown(Error)
}

// MARK: - Network Errors

/// ネットワーク関連のエラー
enum NetworkError: Error {
    /// タイムアウト
    case timeout

    /// 接続失敗
    case connectionFailed

    /// DNS エラー
    case dnsError

    /// ネットワーク接続なし
    case noConnection

    /// その他のネットワークエラー
    case other(Error)
}

// MARK: - API Errors

/// Google Calendar API 関連のエラー
enum APIError: Error {
    /// 認証エラー (401)
    case unauthorized

    /// アクセス拒否 (403)
    case forbidden

    /// リソース不在 (404)
    case notFound

    /// レート制限 (429)
    case rateLimited

    /// トークン失効 (410)
    case tokenExpired

    /// サーバーエラー (5xx)
    case serverError(Int)

    /// 無効なレスポンス
    case invalidResponse

    /// デコードエラー
    case decodingError(Error)

    /// その他の API エラー
    case other(Int, String?)
}

// MARK: - Local Data Errors

/// ローカルデータベース関連のエラー
enum LocalDataError: Error {
    /// データベース書き込み失敗
    case writeFailed

    /// データベース読み込み失敗
    case readFailed

    /// データ整合性エラー
    case dataIntegrityError

    /// ストレージ容量不足
    case storageFull

    /// データが見つからない
    case notFound

    /// その他のローカルデータエラー
    case other(Error)
}

// MARK: - Error Extensions

extension CaleNoteError: LocalizedError {
    /// ユーザーに表示するエラーメッセージ
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return error.localizedDescription
        case .apiError(let error):
            return error.localizedDescription
        case .localDataError(let error):
            return error.localizedDescription
        case .syncError(let message):
            return L10n.tr("error.sync", message)
        case .unknown(let error):
            return L10n.tr("error.unknown", error.localizedDescription)
        }
    }

    /// エラーの回復提案
    var recoverySuggestion: String? {
        switch self {
        case .networkError(.noConnection):
            return L10n.tr("error.recovery.no_connection")
        case .networkError(.timeout):
            return L10n.tr("error.recovery.timeout")
        case .apiError(.unauthorized), .apiError(.forbidden):
            return L10n.tr("error.recovery.account")
        case .apiError(.rateLimited):
            return L10n.tr("error.recovery.rate_limited")
        case .apiError(.tokenExpired):
            return L10n.tr("error.recovery.token_expired")
        case .localDataError(.storageFull):
            return L10n.tr("error.recovery.storage_full")
        default:
            return L10n.tr("error.recovery.default")
        }
    }
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .timeout:
            return L10n.tr("error.network.timeout")
        case .connectionFailed:
            return L10n.tr("error.network.connection_failed")
        case .dnsError:
            return L10n.tr("error.network.dns")
        case .noConnection:
            return L10n.tr("error.network.no_connection")
        case .other(let error):
            return L10n.tr("error.network.other", error.localizedDescription)
        }
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return L10n.tr("error.api.unauthorized")
        case .forbidden:
            return L10n.tr("error.api.forbidden")
        case .notFound:
            return L10n.tr("error.api.not_found")
        case .rateLimited:
            return L10n.tr("error.api.rate_limited")
        case .tokenExpired:
            return L10n.tr("error.api.token_expired")
        case .serverError(let code):
            return L10n.tr("error.api.server_error", L10n.number(code))
        case .invalidResponse:
            return L10n.tr("error.api.invalid_response")
        case .decodingError:
            return L10n.tr("error.api.decoding_failed")
        case .other(let code, let message):
            if message != nil {
                return L10n.tr("error.api.other", L10n.number(code))
            }
            return L10n.tr("error.api.other", L10n.number(code))
        }
    }
}

extension LocalDataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return L10n.tr("error.local.write_failed")
        case .readFailed:
            return L10n.tr("error.local.read_failed")
        case .dataIntegrityError:
            return L10n.tr("error.local.integrity_failed")
        case .storageFull:
            return L10n.tr("error.local.storage_full")
        case .notFound:
            return L10n.tr("error.local.not_found")
        case .other(let error):
            return L10n.tr("error.local.other", error.localizedDescription)
        }
    }
}

// MARK: - Log Descriptions

extension CaleNoteError {
    var logDescription: String {
        switch self {
        case .networkError(let error):
            return error.logDescription
        case .apiError(let error):
            return error.logDescription
        case .localDataError(let error):
            return error.logDescription
        case .syncError(let message):
            return "Sync error: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

extension NetworkError {
    var logDescription: String {
        switch self {
        case .timeout:
            return "Network timeout"
        case .connectionFailed:
            return "Network connection failed"
        case .dnsError:
            return "DNS error"
        case .noConnection:
            return "No network connection"
        case .other(let error):
            return "Other network error: \(error.localizedDescription)"
        }
    }
}

extension APIError {
    var logDescription: String {
        switch self {
        case .unauthorized:
            return "API unauthorized"
        case .forbidden:
            return "API forbidden"
        case .notFound:
            return "API not found"
        case .rateLimited:
            return "API rate limited"
        case .tokenExpired:
            return "API token expired"
        case .serverError(let code):
            return "API server error: \(code)"
        case .invalidResponse:
            return "API invalid response"
        case .decodingError:
            return "API decoding error"
        case .other(let code, let message):
            if let message {
                return "API error (\(code)): \(message)"
            }
            return "API error (\(code))"
        }
    }
}

extension LocalDataError {
    var logDescription: String {
        switch self {
        case .writeFailed:
            return "Local data write failed"
        case .readFailed:
            return "Local data read failed"
        case .dataIntegrityError:
            return "Local data integrity error"
        case .storageFull:
            return "Local data storage full"
        case .notFound:
            return "Local data not found"
        case .other(let error):
            return "Local data error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Retry Decision

extension CaleNoteError {
    /// このエラーがリトライ可能かどうか
    var isRetryable: Bool {
        switch self {
        case .networkError(let error):
            return error.isRetryable
        case .apiError(let error):
            return error.isRetryable
        case .localDataError:
            return false // ローカルデータエラーは基本的にリトライしない
        case .syncError:
            return true
        case .unknown:
            return false
        }
    }
}

extension NetworkError {
    var isRetryable: Bool {
        switch self {
        case .timeout, .connectionFailed, .noConnection:
            return true
        case .dnsError, .other:
            return false
        }
    }
}

extension APIError {
    var isRetryable: Bool {
        switch self {
        case .serverError:
            return true // 5xx エラーはリトライ対象
        case .rateLimited:
            return true // レート制限後のリトライは可能
        case .tokenExpired:
            return true // トークン更新後にリトライ可能
        case .unauthorized, .forbidden, .notFound, .invalidResponse, .decodingError, .other:
            return false // 4xx エラー（410以外）はリトライ対象外
        }
    }
}
