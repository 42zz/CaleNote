import Foundation
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// 同期失敗をCrashlyticsに送信するユーティリティ
enum SyncErrorReporter {
    /// 同期失敗をCrashlyticsに送信
    /// - Parameters:
    ///   - error: エラーオブジェクト
    ///   - syncType: 同期種別（"incremental", "full", "archive", "journal_push", "calendar_list"）
    ///   - calendarId: カレンダーID（ハッシュ化して送信）
    ///   - phase: 処理フェーズ（"short_term", "long_term", "resend"）
    ///   - had410Fallback: syncTokenフォールバック有無
    ///   - httpStatusCode: HTTPステータスコード（取得可能な場合）
    static func reportSyncFailure(
        error: Error,
        syncType: String,
        calendarId: String?,
        phase: String,
        had410Fallback: Bool = false,
        httpStatusCode: Int? = nil
    ) {
        // カレンダーIDをハッシュ化
        let calendarIdHash = calendarId.map { SyncLog.hashCalendarId($0) }
        
        // エラー情報を取得
        let errorType = String(describing: type(of: error))
        
        // HTTPステータスコードを取得（NSErrorから取得を試みる）
        var finalHttpStatusCode = httpStatusCode
        if finalHttpStatusCode == nil {
            if let nsError = error as NSError? {
                // userInfoから取得を試みる
                if let statusCode = nsError.userInfo["HTTPStatusCode"] as? Int {
                    finalHttpStatusCode = statusCode
                } else if nsError.domain == "GoogleCalendarClient" {
                    // GoogleCalendarClientのNSErrorはcodeにHTTPステータスコードが入っている
                    let code = nsError.code
                    if code >= 200 && code < 600 {
                        finalHttpStatusCode = code
                    }
                }
            }
            
            // CalendarSyncError.syncTokenExpiredの場合は410
            // 型名で判定（enumなので直接比較できない）
            let errorTypeName = String(describing: type(of: error))
            if errorTypeName == "CalendarSyncError" {
                finalHttpStatusCode = 410
            }
        }
        
        // Crashlyticsに送信（条件付きコンパイル）
        #if canImport(FirebaseCrashlytics)
        let crashlytics = Crashlytics.crashlytics()
        
        // カスタムキーを設定
        crashlytics.setCustomValue(syncType, forKey: "sync_type")
        if let hash = calendarIdHash {
            crashlytics.setCustomValue(hash, forKey: "calendar_id_hash")
        }
        crashlytics.setCustomValue(phase, forKey: "sync_phase")
        crashlytics.setCustomValue(had410Fallback, forKey: "had_410_fallback")
        if let statusCode = finalHttpStatusCode {
            crashlytics.setCustomValue(statusCode, forKey: "http_status_code")
        }
        crashlytics.setCustomValue(errorType, forKey: "error_type")
        
        // 非致命的エラーとして記録
        let nsError = error as NSError
        crashlytics.recordError(nsError, userInfo: [
            "sync_type": syncType,
            "sync_phase": phase,
            "had_410_fallback": had410Fallback,
            "error_type": errorType,
            "calendar_id_hash": calendarIdHash ?? "unknown"
        ])
        #else
        // Firebase Crashlyticsが設定されていない場合はログ出力のみ
        print("[SyncErrorReporter] Sync failure - Type: \(syncType), Phase: \(phase), Error: \(errorType), CalendarHash: \(calendarIdHash ?? "unknown"), HTTP: \(finalHttpStatusCode?.description ?? "unknown"), 410Fallback: \(had410Fallback)")
        #endif
    }
    
    /// エラーからHTTPステータスコードを抽出
    static func extractHttpStatusCode(from error: Error) -> Int? {
        // CalendarSyncError.syncTokenExpiredの場合は410
        let errorTypeName = String(describing: type(of: error))
        if errorTypeName == "CalendarSyncError" {
            return 410
        }
        
        if let nsError = error as NSError? {
            // userInfoから取得を試みる
            if let statusCode = nsError.userInfo["HTTPStatusCode"] as? Int {
                return statusCode
            }
            
            // GoogleCalendarClientのNSErrorはcodeにHTTPステータスコードが入っている
            if nsError.domain == "GoogleCalendarClient" {
                let code = nsError.code
                if code >= 200 && code < 600 {
                    return code
                }
            }
            
            // NSErrorのcodeがHTTPステータスコードの場合がある
            if nsError.domain == "NSURLErrorDomain" || nsError.domain.contains("HTTP") {
                let code = nsError.code
                if code > 0 && code < 1000 {
                    return code
                }
            }
        }
        return nil
    }
}

