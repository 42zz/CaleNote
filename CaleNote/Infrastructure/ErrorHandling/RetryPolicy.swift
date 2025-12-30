//
//  RetryPolicy.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/28.
//

import Foundation

/// リトライポリシーの設定
struct RetryPolicy {
    /// 最大リトライ回数
    let maxRetries: Int

    /// 初回リトライまでの待機時間（秒）
    let initialDelay: TimeInterval

    /// 待機時間の倍率（Exponential Backoff）
    let backoffMultiplier: Double

    /// 最大待機時間（秒）
    let maxDelay: TimeInterval

    // MARK: - Default Policies

    /// デフォルトのリトライポリシー
    static let `default` = RetryPolicy(
        maxRetries: 3,
        initialDelay: 1.0,
        backoffMultiplier: 2.0,
        maxDelay: 30.0
    )

    /// 積極的なリトライポリシー（ユーザー操作時）
    static let aggressive = RetryPolicy(
        maxRetries: 5,
        initialDelay: 0.5,
        backoffMultiplier: 2.0,
        maxDelay: 10.0
    )

    /// 控えめなリトライポリシー（バックグラウンド同期時）
    static let conservative = RetryPolicy(
        maxRetries: 3,
        initialDelay: 5.0,
        backoffMultiplier: 3.0,
        maxDelay: 60.0
    )

    // MARK: - Retry Calculation

    /// 指定されたリトライ回数での待機時間を計算
    /// - Parameter retryCount: 現在のリトライ回数（0-indexed）
    /// - Returns: 待機時間（秒）
    func delay(for retryCount: Int) -> TimeInterval {
        let exponentialDelay = initialDelay * pow(backoffMultiplier, Double(retryCount))
        return min(exponentialDelay, maxDelay)
    }

    /// リトライを継続すべきかどうか
    /// - Parameter retryCount: 現在のリトライ回数（0-indexed）
    /// - Returns: リトライを継続する場合は true
    func shouldRetry(retryCount: Int) -> Bool {
        return retryCount < maxRetries
    }
}

// MARK: - Retry Executor

/// リトライロジックを実行するユーティリティ
actor RetryExecutor {
    /// リトライポリシーに基づいて処理を実行
    /// - Parameters:
    ///   - policy: リトライポリシー
    ///   - operation: 実行する非同期処理
    /// - Returns: 処理の結果
    /// - Throws: 最終的に失敗した場合のエラー
    static func execute<T>(
        policy: RetryPolicy = .default,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var retryCount = 0

        while retryCount <= policy.maxRetries {
            do {
                return try await operation()
            } catch let error as CaleNoteError {
                lastError = error

                // リトライ可能なエラーかチェック
                guard error.isRetryable else {
                    throw error
                }

                // リトライ回数をチェック
                guard policy.shouldRetry(retryCount: retryCount) else {
                    throw error
                }

                // 待機
                let delay = policy.delay(for: retryCount)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                retryCount += 1
            } catch {
                // CaleNoteError でない場合は即座に throw
                throw error
            }
        }

        // 最終的に失敗した場合
        throw lastError ?? CaleNoteError.unknown(NSError(domain: "RetryExecutor", code: -1))
    }

    /// リトライポリシーに基づいて処理を実行（Result 型を返す版）
    /// - Parameters:
    ///   - policy: リトライポリシー
    ///   - operation: 実行する非同期処理
    /// - Returns: 処理の結果を含む Result
    static func executeWithResult<T>(
        policy: RetryPolicy = .default,
        operation: @escaping () async throws -> T
    ) async -> Result<T, Error> {
        do {
            let result = try await execute(policy: policy, operation: operation)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}
