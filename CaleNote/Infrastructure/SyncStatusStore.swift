import Foundation
import SwiftUI
import Combine

/// 同期ステータスを管理するストア
/// 同期通知の代わりに、右下のステータスアイコンで状態を表示する
@MainActor
class SyncStatusStore: ObservableObject {
    @Published var status: SyncStatus = .idle
    @Published var errorMessage: String?
    @Published var successDetails: String?

    /// 同期状態の種類
    enum SyncStatus {
        case idle       // 何もしていない（アイコン非表示）
        case syncing    // 同期中
        case success    // 同期成功（一時的に表示後、自動でidleに戻る）
        case error      // 同期エラー（タップで再試行可能）
    }

    init() {}

    /// 同期開始を通知
    func setSyncing() {
        status = .syncing
        errorMessage = nil
        successDetails = nil
        print("📡 SyncStatusStore: syncing")
    }

    /// 同期成功を通知（詳細情報付き）
    /// - Parameter details: 成功時の詳細メッセージ（更新件数など）
    func setSuccess(details: String? = nil) {
        status = .success
        successDetails = details
        errorMessage = nil
        print("✅ SyncStatusStore: success - \(details ?? "")")

        // 1.5秒後に自動的にidleに戻る
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if status == .success {
                status = .idle
                successDetails = nil
                print("💤 SyncStatusStore: auto-fade to idle")
            }
        }
    }

    /// 同期エラーを通知
    /// - Parameter message: エラーメッセージ
    func setError(_ message: String) {
        status = .error
        errorMessage = message
        successDetails = nil
        print("❌ SyncStatusStore: error - \(message)")
    }

    /// 手動でidleに戻す
    func reset() {
        status = .idle
        errorMessage = nil
        successDetails = nil
        print("🔄 SyncStatusStore: reset to idle")
    }
}
