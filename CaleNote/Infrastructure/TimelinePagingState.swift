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
    /// カーソル方式: 検索範囲を段階的に過去へ進めることで、有効イベントが疎でも深い過去まで到達可能
    /// 戻り値: (イベント配列, まだデータがあるか, 取得詳細)
    private func fetchPastEvents(
        fromDayKey: Int,
        limit: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Bool, String) {
        // カーソル方式: 毎回検索範囲を過去方向へシフトさせる
        let batchSize = limit * 5  // 固定バッチサイズ
        var cursorDayKey = fromDayKey
        var filtered: [ArchivedCalendarEvent] = []
        var fetchDetails = ""
        var batchCount = 0
        let maxBatches = 50  // 安全弁（50バッチ = limit*5*50 = 最大7500件相当の探索）

        while filtered.count < limit && batchCount < maxBatches {
            batchCount += 1

            // 現在のカーソル位置より古い範囲から batchSize 件取得
            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey < cursorDayKey
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.start, order: .reverse)]
            descriptor.fetchLimit = batchSize

            let batch = try modelContext.fetch(descriptor)

            // 有効なカレンダーのイベントのみフィルタして追加
            let filteredBatch = batch.filter { enabledCalendarIds.contains($0.calendarId) }
            filtered.append(contentsOf: filteredBatch)

            fetchDetails += "バッチ\(batchCount): cursor=\(cursorDayKey), 取得=\(batch.count), フィルタ後=\(filteredBatch.count), 累計=\(filtered.count); "

            // DB終端チェック
            if batch.count < batchSize {
                let result = Array(filtered.prefix(limit))
                fetchDetails += "DB終端到達"
                return (result, false, fetchDetails)
            }

            // 次のカーソル位置を更新（今回取得したバッチの最古日付の1日前）
            if let oldestInBatch = batch.map({ $0.startDayKey }).min() {
                cursorDayKey = oldestInBatch - 1

                // カーソルが0以下になったら終了（日付の下限）
                if cursorDayKey <= 0 {
                    let result = Array(filtered.prefix(limit))
                    fetchDetails += "カーソル下限到達"
                    return (result, false, fetchDetails)
                }
            } else {
                // バッチが空（通常ありえないがガード）
                let result = Array(filtered.prefix(limit))
                fetchDetails += "バッチ空"
                return (result, false, fetchDetails)
            }
        }

        // maxBatchesに達した場合でも、取得できた分を返す
        let result = Array(filtered.prefix(limit))
        let hasMore = filtered.count >= limit
        fetchDetails += hasMore ? "limit到達" : "maxBatch到達"
        return (result, hasMore, fetchDetails)
    }
}
