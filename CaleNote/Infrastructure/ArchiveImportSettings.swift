import Foundation
import SwiftData

/// 長期キャッシュ取得状態を管理するクラス
enum ArchiveImportSettings {
    private static let completedKey = "archiveImport_completed"
    private static let inProgressKey = "archiveImport_inProgress"

    /// 指定されたカレンダーの長期キャッシュ取得が完了しているかを確認
    static func isCompleted(calendarId: String) -> Bool {
        let completed = UserDefaults.standard.stringArray(forKey: completedKey) ?? []
        return completed.contains(calendarId)
    }

    /// 指定されたカレンダーの長期キャッシュ取得を完了済みとしてマーク
    static func markCompleted(calendarId: String) {
        var completed = UserDefaults.standard.stringArray(forKey: completedKey) ?? []
        if !completed.contains(calendarId) {
            completed.append(calendarId)
            UserDefaults.standard.set(completed, forKey: completedKey)
        }

        // 取得中フラグをクリア
        removeInProgress(calendarId: calendarId)
    }

    /// 指定されたカレンダーの長期キャッシュ取得が進行中かを確認
    static func isInProgress(calendarId: String) -> Bool {
        let inProgress = UserDefaults.standard.stringArray(forKey: inProgressKey) ?? []
        return inProgress.contains(calendarId)
    }

    /// 指定されたカレンダーの長期キャッシュ取得を進行中としてマーク
    static func markInProgress(calendarId: String) {
        var inProgress = UserDefaults.standard.stringArray(forKey: inProgressKey) ?? []
        if !inProgress.contains(calendarId) {
            inProgress.append(calendarId)
            UserDefaults.standard.set(inProgress, forKey: inProgressKey)
        }
    }

    /// 指定されたカレンダーの進行中フラグを削除
    static func removeInProgress(calendarId: String) {
        var inProgress = UserDefaults.standard.stringArray(forKey: inProgressKey) ?? []
        inProgress.removeAll { $0 == calendarId }
        UserDefaults.standard.set(inProgress, forKey: inProgressKey)
    }

    /// 指定されたカレンダーの長期キャッシュ取得をバックグラウンドで開始
    @MainActor
    static func startBackgroundImport(
        for calendar: CachedCalendar,
        auth: GoogleAuthService,
        modelContext: ModelContext
    ) {
        // 既に完了済みまたは取得中の場合はスキップ
        if isCompleted(calendarId: calendar.calendarId) || isInProgress(calendarId: calendar.calendarId) {
            return
        }

        // バックグラウンドタスクで取得開始
        Task(priority: .background) {
            markInProgress(calendarId: calendar.calendarId)

            do {
                let archiveSync = ArchiveSyncService()
                try await archiveSync.importAllEventsToArchive(
                    auth: auth,
                    modelContext: modelContext,
                    calendars: [calendar]
                ) { _ in
                    // 進捗は記録しない（サイレント実行）
                }

                markCompleted(calendarId: calendar.calendarId)
            } catch {
                // エラーが発生した場合は進行中フラグをクリア
                removeInProgress(calendarId: calendar.calendarId)
                print("長期キャッシュ取得エラー (\(calendar.calendarId)): \(error.localizedDescription)")
            }
        }
    }
}
