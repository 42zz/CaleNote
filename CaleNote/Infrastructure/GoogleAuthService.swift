import Combine
import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GoogleAuthService: ObservableObject {
  @Published private(set) var user: GIDGoogleUser?

  private let calendarScope = "https://www.googleapis.com/auth/calendar"

  func restorePreviousSignInIfPossible() async {
    do {
      let restored = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
      self.user = restored
    } catch {
      self.user = nil
    }
  }

  func signIn() async throws {
    guard let presentingVC = Self.findPresentingViewController() else {
      throw NSError(
        domain: "GoogleAuthService", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "presentingViewController が見つかりません"])
    }

    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
    self.user = result.user
  }

  func signOut() {
    GIDSignIn.sharedInstance.signOut()
    self.user = nil
  }

  /// Calendar API を叩くために必要なスコープを付与（未付与なら許可UIが出る）
  func ensureCalendarScopeGranted() async throws {
    guard let currentUser = self.user else {
      throw NSError(
        domain: "GoogleAuthService", code: 10,
        userInfo: [NSLocalizedDescriptionKey: "未ログインです"])
    }

    if currentUser.grantedScopes?.contains(calendarScope) == true {
      return
    }

    guard let presentingVC = Self.findPresentingViewController() else {
      throw NSError(
        domain: "GoogleAuthService", code: 11,
        userInfo: [NSLocalizedDescriptionKey: "presentingViewController が見つかりません"])
    }

    // addScopes は callback なので continuation で async 化
    // ★ SDKのリネームに合わせて presenting: を使う
    let resultUser: GIDGoogleUser = try await withCheckedThrowingContinuation {
      (cont: CheckedContinuation<GIDGoogleUser, Error>) in
      currentUser.addScopes([calendarScope], presenting: presentingVC) { signInResult, error in
        if let error {
          cont.resume(throwing: error)
          return
        }
        guard let signInResult else {
          cont.resume(
            throwing: NSError(
              domain: "GoogleAuthService", code: 12,
              userInfo: [NSLocalizedDescriptionKey: "addScopes の結果が空です"]))
          return
        }
        cont.resume(returning: signInResult.user)
      }
    }

    // ★ Sendableクロージャ外（MainActor上）で user を更新する
    self.user = resultUser
  }

  /// アクセストークンを返す（必要なら更新してから返す）
  func validAccessToken() async throws -> String {
    guard let currentUser = self.user else {
      throw NSError(
        domain: "GoogleAuthService", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "未ログインです"])
    }

    let refreshed = try await currentUser.refreshTokensIfNeeded()

    // ★ accessToken が Optional じゃないSDK向け（?. を使わない）
    let token = refreshed.accessToken.tokenString
    if token.isEmpty {
      throw NSError(
        domain: "GoogleAuthService", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "access token が取得できません"])
    }
    return token
  }

  private static func findPresentingViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController
  }
}
