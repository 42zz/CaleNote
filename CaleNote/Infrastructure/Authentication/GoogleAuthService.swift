//
//  GoogleAuthService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation
import Combine
import GoogleSignIn
import OSLog

/// Google 認証を管理するサービス
@MainActor
final class GoogleAuthService: ObservableObject {
    // MARK: - Singleton

    static let shared = GoogleAuthService()

    // MARK: - Published Properties

    /// 現在のユーザー
    @Published private(set) var currentUser: GIDGoogleUser?

    /// 認証状態
    @Published private(set) var isAuthenticated = false

    /// 認証中フラグ
    @Published private(set) var isAuthenticating = false

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "GoogleAuth")

    // MARK: - Constants

    /// Google Calendar API のスコープ
    private let calendarScopes = [
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/calendar.events"
    ]

    // MARK: - Initialization

    private init() {
        // 前回のサインイン状態を復元
        Task {
            await restorePreviousSignIn()
        }
    }

    // MARK: - Authentication Methods

    /// Google サインインを開始
    /// - Throws: 認証エラー
    func signIn() async throws {
        logger.info("Starting Google Sign-In")
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            // Client ID を取得
            guard let clientID = getClientID() else {
                throw CaleNoteError.apiError(.other(0, "Google Client ID が設定されていません"))
            }

            // GIDConfiguration を作成
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config

            // Root View Controller を取得
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw CaleNoteError.apiError(.other(0, "Root View Controller が見つかりません"))
            }

            // サインイン実行
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: calendarScopes
            )

            currentUser = result.user
            isAuthenticated = true

            logger.info("Google Sign-In successful: \(result.user.userID ?? "unknown")")
        } catch let error as GIDSignInError {
            logger.error("Google Sign-In failed: \(error.localizedDescription)")
            throw convertGIDError(error)
        } catch {
            logger.error("Unexpected error during sign-in: \(error.localizedDescription)")
            throw CaleNoteError.unknown(error)
        }
    }

    /// サインアウト
    func signOut() {
        logger.info("Signing out from Google")
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        isAuthenticated = false
    }

    /// 前回のサインイン状態を復元
    func restorePreviousSignIn() async {
        logger.info("Restoring previous sign-in state")

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            self.currentUser = user
            self.isAuthenticated = true
            self.logger.info("Previous sign-in restored: \(user.userID ?? "unknown")")
        } catch {
            self.logger.warning("Failed to restore previous sign-in: \(error.localizedDescription)")
        }
    }

    /// アクセストークンを取得（必要に応じてリフレッシュ）
    /// - Returns: アクセストークン
    /// - Throws: トークン取得エラー
    func getAccessToken() async throws -> String {
        guard let user = currentUser else {
            throw CaleNoteError.apiError(.unauthorized)
        }

        // トークンの有効期限をチェック
        if let expirationDate = user.accessToken.expirationDate,
           expirationDate <= Date() {
            // トークンをリフレッシュ
            try await refreshTokenIfNeeded()
        }

        return user.accessToken.tokenString
    }

    /// トークンをリフレッシュ（必要な場合のみ）
    /// - Throws: リフレッシュエラー
    func refreshTokenIfNeeded() async throws {
        guard let user = currentUser else {
            throw CaleNoteError.apiError(.unauthorized)
        }

        logger.info("Refreshing access token")

        do {
            let refreshedUser = try await user.refreshTokensIfNeeded()
            currentUser = refreshedUser
            logger.info("Access token refreshed successfully")
        } catch let error as GIDSignInError {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            throw convertGIDError(error)
        } catch {
            logger.error("Unexpected error during token refresh: \(error.localizedDescription)")
            throw CaleNoteError.unknown(error)
        }
    }

    /// 追加のスコープをリクエスト
    /// - Parameter scopes: リクエストするスコープ
    /// - Throws: スコープリクエストエラー
    func requestAdditionalScopes(_ scopes: [String]) async throws {
        guard let user = currentUser else {
            throw CaleNoteError.apiError(.unauthorized)
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw CaleNoteError.apiError(.other(0, "Root View Controller が見つかりません"))
        }

        logger.info("Requesting additional scopes: \(scopes)")

        do {
            let result = try await user.addScopes(scopes, presenting: rootViewController)
            currentUser = result.user
            logger.info("Additional scopes granted")
        } catch let error as GIDSignInError {
            logger.error("Failed to request additional scopes: \(error.localizedDescription)")
            throw convertGIDError(error)
        }
    }

    // MARK: - Helper Methods

    /// Info.plist から Google Client ID を取得
    /// - Returns: Client ID（存在する場合）
    private func getClientID() -> String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let clientID = dict["CLIENT_ID"] as? String else {
            // GoogleService-Info.plist がない場合は Info.plist から取得を試みる
            return Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        }
        return clientID
    }

    /// GIDSignInError を CaleNoteError に変換
    /// - Parameter error: GIDSignInError
    /// - Returns: CaleNoteError
    private func convertGIDError(_ error: GIDSignInError) -> CaleNoteError {
        switch error.code {
        case .canceled:
            return .apiError(.other(Int(error.code.rawValue), "サインインがキャンセルされました"))
        case .hasNoAuthInKeychain:
            return .apiError(.unauthorized)
        case .unknown:
            return .unknown(error)
        default:
            return .apiError(.other(Int(error.code.rawValue), error.localizedDescription))
        }
    }
}

// MARK: - Computed Properties

extension GoogleAuthService {
    /// 現在のユーザーのメールアドレス
    var userEmail: String? {
        currentUser?.profile?.email
    }

    /// 現在のユーザーの名前
    var userName: String? {
        currentUser?.profile?.name
    }

    /// 現在のユーザーのプロフィール画像 URL
    var userImageURL: URL? {
        currentUser?.profile?.imageURL(withDimension: 120)
    }
}
