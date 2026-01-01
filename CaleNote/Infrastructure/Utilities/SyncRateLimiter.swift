//
//  SyncRateLimiter.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Foundation

/// API呼び出しのレート制限を管理するアクター
actor SyncRateLimiter {
    /// 共有インスタンス
    static let shared = SyncRateLimiter()
    
    /// 最短リクエスト間隔（秒）
    private let minInterval: TimeInterval
    
    /// 最後にリクエストを実行した時刻
    private var lastRequestTime: Date?
    
    /// 初期化
    /// - Parameter minInterval: 最短リクエスト間隔（デフォルト: 5秒）
    init(minInterval: TimeInterval = 5.0) {
        self.minInterval = minInterval
    }
    
    /// 実行許可を取得（必要に応じて待機）
    func acquire() async throws {
        let now = Date()
        
        if let lastRequestTime = lastRequestTime {
            let elapsed = now.timeIntervalSince(lastRequestTime)
            if elapsed < minInterval {
                let waitTime = minInterval - elapsed
                // 秒数をナノ秒に変換（1秒 = 1,000,000,000ナノ秒）
                let nanoseconds = UInt64(waitTime * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        
        lastRequestTime = Date()
    }
}
