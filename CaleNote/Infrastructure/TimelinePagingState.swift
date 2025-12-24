import Foundation
import SwiftData

/// タイムライン過去側ページング状態管理
/// 短期キャッシュ（CachedCalendarEvent）を使い切った後、
/// 長期キャッシュ（ArchivedCalendarEvent）から過去を段階表示する
@MainActor
@Observable
final class TimelinePagingState {
    /// 過去方向のロード中フラグ
    var isLoadingPast: Bool = false

    /// 過去方向のロードが完了（これ以上データがない）
    var hasReachedEarliestData: Bool = false

    /// 現在ロード済みのアーカイブイベント（長期キャッシュから取得）
    var loadedArchivedEvents: [ArchivedCalendarEvent] = []

    /// 最も古い（過去側）にロード済みの日付キー（YYYYMMDD形式）
    /// TimelineViewから参照可能（読み取り専用プロパティとして公開）
    var earliestPagingDayKey: Int? {
        earliestLoadedDayKey
    }

    /// 内部で使用する境界キー
    private var earliestLoadedDayKey: Int?

    init() {}

    /// ページング状態をリセット（再初期化用）
    func reset() {
        isLoadingPast = false
        hasReachedEarliestData = false
        loadedArchivedEvents = []
        earliestLoadedDayKey = nil
    }

    /// 過去方向のページをロード
    /// 短期キャッシュの最古日付より古い長期キャッシュイベントを取得
    func loadPastPage(
        fromDayKey: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async {
        guard !isLoadingPast, !hasReachedEarliestData else {
            print("📄 過去ページロードスキップ: isLoadingPast=\(isLoadingPast), hasReachedEarliestData=\(hasReachedEarliestData)")
            return
        }

        print("📄 過去ページロード開始: fromDayKey=\(fromDayKey), enabledCalendarIds=\(enabledCalendarIds.count)件")
        isLoadingPast = true
        defer { isLoadingPast = false }

        do {
            let (newEvents, hasMore, fetchDetails) = try await fetchPastEvents(
                fromDayKey: fromDayKey,
                limit: AppConfig.Timeline.pageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            print("📄 過去ページロード結果: 取得件数=\(newEvents.count), hasMore=\(hasMore), 詳細=\(fetchDetails)")

            if !newEvents.isEmpty {
                // 重複排除：既存のuid集合を作成
                let existingUids = Set(loadedArchivedEvents.map { $0.uid })
                let uniqueNewEvents = newEvents.filter { !existingUids.contains($0.uid) }

                print("📄 重複排除結果: 新規イベント=\(newEvents.count)件, ユニーク=\(uniqueNewEvents.count)件")

                // マージ（降順を維持）
                loadedArchivedEvents.append(contentsOf: uniqueNewEvents)
                loadedArchivedEvents.sort { $0.start > $1.start }

                // 境界キーを更新
                if let earliest = uniqueNewEvents.min(by: { $0.startDayKey < $1.startDayKey }) {
                    let oldEarliest = earliestLoadedDayKey
                    earliestLoadedDayKey = earliest.startDayKey
                    print("📄 境界キー更新: \(oldEarliest ?? 0) → \(earliestLoadedDayKey!)")
                }
            }

            // データが尽きたかチェック
            if !hasMore {
                print("📄 終端到達: 理由=\(fetchDetails)")
                hasReachedEarliestData = true
            }
        } catch {
            print("📄❌ 過去ページロードエラー: \(error.localizedDescription)")
        }
    }

    /// 過去方向のイベントを取得（startDayKey < fromDayKey の範囲で limit 件）
    /// 戻り値: (イベント配列, まだデータがあるか, 取得詳細)
    private func fetchPastEvents(
        fromDayKey: Int,
        limit: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Bool, String) {
        // 有効カレンダーIDでフィルタしながら、limit件取得するまでループ
        var fetchLimit = limit * 10
        let maxFetchLimit = limit * 100
        var filtered: [ArchivedCalendarEvent] = []
        var fetchDetails = ""

        while filtered.count < limit && fetchLimit <= maxFetchLimit {
            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey < fromDayKey
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.start, order: .reverse)]
            descriptor.fetchLimit = fetchLimit

            let allEvents = try modelContext.fetch(descriptor)

            // 有効なカレンダーのイベントのみフィルタ
            filtered = allEvents.filter { enabledCalendarIds.contains($0.calendarId) }

            fetchDetails = "fetchLimit=\(fetchLimit), 全取得=\(allEvents.count)件, フィルタ後=\(filtered.count)件"

            // データベースに全データを取得した場合は終了
            if allEvents.count < fetchLimit {
                let result = Array(filtered.prefix(limit))
                fetchDetails += ", DB終端到達"
                return (result, false, fetchDetails)  // まだデータがない
            }

            // まだ足りない場合は再試行
            if filtered.count < limit {
                fetchLimit *= 2
                fetchDetails += ", リトライ中"
            }
        }

        let result = Array(filtered.prefix(limit))
        let hasMore = filtered.count >= limit
        fetchDetails += ", hasMore=\(hasMore)"
        return (result, hasMore, fetchDetails)
    }
}
