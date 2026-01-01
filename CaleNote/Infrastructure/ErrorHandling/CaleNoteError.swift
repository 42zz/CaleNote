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
            return "同期エラー: \(message)"
        case .unknown(let error):
            return "予期しないエラーが発生しました: \(error.localizedDescription)"
        }
    }

    /// エラーの回復提案
    var recoverySuggestion: String? {
        switch self {
        case .networkError(.noConnection):
            return "インターネット接続を確認してください"
        case .networkError(.timeout):
            return "時間をおいて再度お試しください"
        case .apiError(.unauthorized), .apiError(.forbidden):
            return "アカウント設定を確認してください"
        case .apiError(.rateLimited):
            return "しばらく待ってから再度お試しください"
        case .apiError(.tokenExpired):
            return "再度ログインしてください"
        case .localDataError(.storageFull):
            return "デバイスの空き容量を確保してください"
        default:
            return "問題が解決しない場合は、アプリを再起動してください"
        }
    }
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "通信がタイムアウトしました"
        case .connectionFailed:
            return "サーバーに接続できませんでした"
        case .dnsError:
            return "DNS エラーが発生しました"
        case .noConnection:
            return "インターネット接続がありません"
        case .other(let error):
            return "ネットワークエラーが発生しました"
        }
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "認証に失敗しました"
        case .forbidden:
            return "アクセスが拒否されました"
        case .notFound:
            return "リソースが見つかりませんでした"
        case .rateLimited:
            return "リクエスト制限に達しました"
        case .tokenExpired:
            return "認証トークンが失効しました"
        case .serverError(let code):
            return "サーバーエラーが発生しました（\(code)）"
        case .invalidResponse:
            return "無効なレスポンスを受信しました"
        case .decodingError:
            return "データの解析に失敗しました"
        case .other(let code, let message):
            if message != nil {
                return "API エラー（\(code)）が発生しました"
            }
            return "API エラー（\(code)）が発生しました"
        }
    }
}

extension LocalDataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return "データの保存に失敗しました"
        case .readFailed:
            return "データの読み込みに失敗しました"
        case .dataIntegrityError:
            return "データの整合性エラーが発生しました"
        case .storageFull:
            return "ストレージ容量が不足しています"
        case .notFound:
            return "データが見つかりませんでした"
        case .other(let error):
            return "ローカルデータエラーが発生しました"
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
