import Foundation
import SwiftData

/// タイムラインのページング状態を管理するクラス
@MainActor
@Observable
final class TimelinePagingState {
    /// 最も古い（過去側）にロード済みの日付キー（YYYYMMDD形式）
    var earliestLoadedDayKey: Int?

    /// 最も新しい（未来側）にロード済みの日付キー（YYYYMMDD形式）
    var latestLoadedDayKey: Int?

    /// 過去方向のロード中フラグ
    var isLoadingPast: Bool = false

    /// 未来方向のロード中フラグ
    var isLoadingFuture: Bool = false

    /// 過去方向のロードが完了（これ以上データがない）
    var hasReachedEarliestData: Bool = false

    /// 未来方向のロードが完了（これ以上データがない）
    var hasReachedLatestData: Bool = false

    /// 現在ロード済みのアーカイブイベント
    var loadedArchivedEvents: [ArchivedCalendarEvent] = []

    /// スクロール位置の復元用アンカー
    var scrollAnchorId: String?

    /// 最後にロードした境界キー（重複ロード防止）
    private var lastPastLoadBoundary: Int?
    private var lastFutureLoadBoundary: Int?

    init() {}
    
    /// ページング状態をリセット（再初期化用）
    func reset() {
        earliestLoadedDayKey = nil
        latestLoadedDayKey = nil
        isLoadingPast = false
        isLoadingFuture = false
        hasReachedEarliestData = false
        hasReachedLatestData = false
        loadedArchivedEvents = []
        scrollAnchorId = nil
        lastPastLoadBoundary = nil
        lastFutureLoadBoundary = nil
    }

    /// 初期ロード（今日を中心に未来側と過去側を両方ロード + ジャーナルの日付範囲も考慮）
    func initialLoad(
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>,
        journalDateRange: (min: Date?, max: Date?)? = nil
    ) async {
        guard !isLoadingPast && !isLoadingFuture else { return }

        isLoadingPast = true
        isLoadingFuture = true

        let today = Calendar.current.startOfDay(for: Date())
        let todayKey = makeDayKey(from: today)

        // デバッグ: データベース全体の件数を確認
        let allEventsDescriptor = FetchDescriptor<ArchivedCalendarEvent>()
        let allEventsCount = (try? modelContext.fetch(allEventsDescriptor).count) ?? 0
        print("🚀 初期ロード開始: データベース全体のアーカイブイベント数=\(allEventsCount), 有効カレンダー数=\(enabledCalendarIds.count)")
        
        if allEventsCount > 0 {
            // サンプルデータを取得して確認
            var sampleDescriptor = FetchDescriptor<ArchivedCalendarEvent>()
            sampleDescriptor.fetchLimit = 5
            sampleDescriptor.sortBy = [SortDescriptor(\.startDayKey, order: .reverse)]
            if let samples = try? modelContext.fetch(sampleDescriptor) {
                let sampleCalendarIds = Set(samples.map { $0.calendarId })
                print("🚀 サンプルカレンダーID: \(sampleCalendarIds)")
            }
        }

        do {
            var allLoadedEvents: [ArchivedCalendarEvent] = []

            print("🚀 初期ロード開始: 今日を中心に前後\(AppConfig.Timeline.initialPageSize)件ずつ取得")

            // 1. 今日を中心に未来側をロード（今日を含む）
            let (futureEvents, futureFilteredCount) = try await loadFutureEvents(
                fromDayKey: todayKey,
                limit: AppConfig.Timeline.initialPageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            allLoadedEvents.append(contentsOf: futureEvents)
            print("🚀 未来側ロード完了: \(futureEvents.count)件")

            // 2. 今日を中心に過去側をロード（今日は含まない）
            let (pastEvents, pastFilteredCount) = try await loadPastEvents(
                fromDayKey: todayKey - 1,  // 今日の前日から
                limit: AppConfig.Timeline.initialPageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            allLoadedEvents.append(contentsOf: pastEvents)
            print("🚀 過去側ロード完了: \(pastEvents.count)件")

            // 重複排除とソート処理を実行（メインスレッドで処理）
            let combined = allLoadedEvents

            // 重複排除（UIDでグループ化）
            var uniqueDict: [String: ArchivedCalendarEvent] = [:]
            for event in combined {
                if uniqueDict[event.uid] == nil {
                    uniqueDict[event.uid] = event
                }
            }

            // ソート（降順）
            let uniqueEvents = Array(uniqueDict.values)
            let allEvents = uniqueEvents.sorted { $0.startDayKey > $1.startDayKey }

            loadedArchivedEvents = allEvents

            // 境界キーを更新
            if let earliest = allEvents.min(by: { $0.startDayKey < $1.startDayKey }) {
                earliestLoadedDayKey = earliest.startDayKey
            }
            if let latest = allEvents.max(by: { $0.startDayKey < $1.startDayKey }) {
                latestLoadedDayKey = latest.startDayKey
            }

            // フィルタ後の件数がlimit未満の場合、これ以上データがないと判断
            if futureFilteredCount < AppConfig.Timeline.initialPageSize {
                hasReachedLatestData = true
                print("🚀 未来データの最後に到達: futureFilteredCount(\(futureFilteredCount)) < limit(\(AppConfig.Timeline.initialPageSize))")
            }
            if pastFilteredCount < AppConfig.Timeline.initialPageSize {
                hasReachedEarliestData = true
                print("🚀 過去データの最後に到達: pastFilteredCount(\(pastFilteredCount)) < limit(\(AppConfig.Timeline.initialPageSize))")
            }

            print("🚀 初期ロード完了: 合計\(allEvents.count)件")

        } catch {
            print("初期ロードエラー: \(error.localizedDescription)")
        }

        isLoadingPast = false
        isLoadingFuture = false
    }

    /// 過去方向のページをロード
    func loadPastPage(modelContext: ModelContext, enabledCalendarIds: Set<String>) async {
        guard !isLoadingPast, !hasReachedEarliestData else {
            print("⚠️ 過去ページロードをスキップ: isLoadingPast=\(isLoadingPast), hasReachedEarliestData=\(hasReachedEarliestData)")
            return
        }
        guard let currentEarliest = earliestLoadedDayKey else {
            print("⚠️ 過去ページロードをスキップ: earliestLoadedDayKeyがnil")
            return
        }

        // 重複ロード防止
        if lastPastLoadBoundary == currentEarliest {
            print("⚠️ 過去ページロードをスキップ: 重複ロード防止 (lastPastLoadBoundary=\(lastPastLoadBoundary ?? 0))")
            return
        }

        print("📄 過去ページロード開始: currentEarliest=\(currentEarliest), 有効カレンダー数=\(enabledCalendarIds.count)")
        isLoadingPast = true
        lastPastLoadBoundary = currentEarliest

        do {
            let (newEvents, filteredCount) = try await loadPastEvents(
                fromDayKey: currentEarliest - 1,
                limit: AppConfig.Timeline.pageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            print("📄 過去ページロード結果: 新規イベント数=\(newEvents.count), フィルタ後件数=\(filteredCount), limit=\(AppConfig.Timeline.pageSize)")

            // フィルタ後の件数がlimit未満の場合、これ以上データがないと判断
            if filteredCount < AppConfig.Timeline.pageSize {
                print("📄 過去データの最後に到達: filteredCount(\(filteredCount)) < limit(\(AppConfig.Timeline.pageSize))")
                hasReachedEarliestData = true
            }
            
            if !newEvents.isEmpty {
                // 重複排除とマージ処理を実行（メインスレッドで処理）
                let existingEvents = loadedArchivedEvents
                
                // 既存イベントのUID集合を作成（重複チェック用）
                let existingUidSet = Set(existingEvents.map { $0.uid })
                
                // 新しいイベントから重複を除外
                let uniqueNewEvents = newEvents.filter { !existingUidSet.contains($0.uid) }
                
                // 既存配列と新しいイベントをマージ（既にソート済みなので効率的にマージ）
                var merged: [ArchivedCalendarEvent] = []
                merged.reserveCapacity(existingEvents.count + uniqueNewEvents.count)
                
                // 既存配列は既に降順ソート済み、新しいイベントも降順ソート済みなので、マージソートを使用
                var existingIndex = 0
                var newIndex = 0
                
                while existingIndex < existingEvents.count && newIndex < uniqueNewEvents.count {
                    if existingEvents[existingIndex].startDayKey > uniqueNewEvents[newIndex].startDayKey {
                        merged.append(existingEvents[existingIndex])
                        existingIndex += 1
                    } else {
                        merged.append(uniqueNewEvents[newIndex])
                        newIndex += 1
                    }
                }
                
                // 残りを追加
                merged.append(contentsOf: existingEvents[existingIndex...])
                merged.append(contentsOf: uniqueNewEvents[newIndex...])
                
                // 状態を更新
                loadedArchivedEvents = merged

                // 境界キーを更新
                if let earliest = newEvents.min(by: { $0.startDayKey < $1.startDayKey }) {
                    earliestLoadedDayKey = earliest.startDayKey
                }
            }
        } catch {
            print("過去ページロードエラー: \(error.localizedDescription)")
        }

        isLoadingPast = false
    }

    /// 未来方向のページをロード
    func loadFuturePage(modelContext: ModelContext, enabledCalendarIds: Set<String>) async {
        guard !isLoadingFuture, !hasReachedLatestData else { return }
        guard let currentLatest = latestLoadedDayKey else { return }

        // 重複ロード防止
        if lastFutureLoadBoundary == currentLatest {
            return
        }

        isLoadingFuture = true
        lastFutureLoadBoundary = currentLatest

        do {
            let (newEvents, filteredCount) = try await loadFutureEvents(
                fromDayKey: currentLatest + 1,
                limit: AppConfig.Timeline.pageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            print("📅 未来ページロード結果: 新規イベント数=\(newEvents.count), フィルタ後件数=\(filteredCount), limit=\(AppConfig.Timeline.pageSize)")

            // フィルタ後の件数がlimit未満の場合、これ以上データがないと判断
            if filteredCount < AppConfig.Timeline.pageSize {
                print("📅 未来データの最後に到達: filteredCount(\(filteredCount)) < limit(\(AppConfig.Timeline.pageSize))")
                hasReachedLatestData = true
            }
            
            if !newEvents.isEmpty {
                // 重複排除とマージ処理を実行（メインスレッドで処理）
                let existingEvents = loadedArchivedEvents
                
                // 既存イベントのUID集合を作成（重複チェック用）
                let existingUidSet = Set(existingEvents.map { $0.uid })
                
                // 新しいイベントから重複を除外
                let uniqueNewEvents = newEvents.filter { !existingUidSet.contains($0.uid) }
                
                // 既存配列と新しいイベントをマージ（既にソート済みなので効率的にマージ）
                var merged: [ArchivedCalendarEvent] = []
                merged.reserveCapacity(existingEvents.count + uniqueNewEvents.count)
                
                // 既存配列は既に降順ソート済み、新しいイベントも降順ソート済みなので、マージソートを使用
                var existingIndex = 0
                var newIndex = 0
                
                while existingIndex < existingEvents.count && newIndex < uniqueNewEvents.count {
                    if existingEvents[existingIndex].startDayKey > uniqueNewEvents[newIndex].startDayKey {
                        merged.append(existingEvents[existingIndex])
                        existingIndex += 1
                    } else {
                        merged.append(uniqueNewEvents[newIndex])
                        newIndex += 1
                    }
                }
                
                // 残りを追加
                merged.append(contentsOf: existingEvents[existingIndex...])
                merged.append(contentsOf: uniqueNewEvents[newIndex...])
                
                // 状態を更新
                loadedArchivedEvents = merged

                // 境界キーを更新
                if let latest = newEvents.max(by: { $0.startDayKey < $1.startDayKey }) {
                    latestLoadedDayKey = latest.startDayKey
                }
            }
        } catch {
            print("未来ページロードエラー: \(error.localizedDescription)")
        }

        isLoadingFuture = false
    }

    /// 最大ロード件数を超えた場合、スクロール方向と逆側をトリム
    func trimIfNeeded(scrollDirection: ScrollDirection) {
        guard loadedArchivedEvents.count > AppConfig.Timeline.maxLoadedItems else { return }

        let excessCount = loadedArchivedEvents.count - AppConfig.Timeline.maxLoadedItems
        let trimCount = max(AppConfig.Timeline.pageSize, excessCount)

        switch scrollDirection {
        case .past:
            // 過去方向にスクロールしている場合は未来側（上）を削る
            trimFutureSide(count: trimCount)
        case .future:
            // 未来方向にスクロールしている場合は過去側（下）を削る
            trimPastSide(count: trimCount)
        }
    }

    /// 未来側（新しい方）からトリム
    private func trimFutureSide(count: Int) {
        guard latestLoadedDayKey != nil else { return }

        // トリム対象の境界キーを計算（ページサイズ単位で削る）
        let sortedEvents = loadedArchivedEvents.sorted { $0.startDayKey > $1.startDayKey }
        guard sortedEvents.count > count else {
            // 全削除はしない
            return
        }

        let newLatestIndex = count
        let newLatestEvent = sortedEvents[newLatestIndex]
        let newLatestDayKey = newLatestEvent.startDayKey

        // 新しい境界より新しいものを削除
        loadedArchivedEvents = loadedArchivedEvents.filter { $0.startDayKey <= newLatestDayKey }
        latestLoadedDayKey = newLatestDayKey
        hasReachedLatestData = false  // トリムしたのでまたロード可能
    }

    /// 過去側（古い方）からトリム
    private func trimPastSide(count: Int) {
        guard earliestLoadedDayKey != nil else { return }

        // トリム対象の境界キーを計算（ページサイズ単位で削る）
        let sortedEvents = loadedArchivedEvents.sorted { $0.startDayKey < $1.startDayKey }
        guard sortedEvents.count > count else {
            // 全削除はしない
            return
        }

        let newEarliestIndex = count
        let newEarliestEvent = sortedEvents[newEarliestIndex]
        let newEarliestDayKey = newEarliestEvent.startDayKey

        // 新しい境界より古いものを削除
        loadedArchivedEvents = loadedArchivedEvents.filter { $0.startDayKey >= newEarliestDayKey }
        earliestLoadedDayKey = newEarliestDayKey
        hasReachedEarliestData = false  // トリムしたのでまたロード可能
    }

    /// 過去方向のイベントをロード（startDayKey < fromDayKey の範囲で降順に limit 件）
    /// 戻り値: (フィルタ後のイベント, フィルタ後の件数（これがlimit未満なら、これ以上データがないことを示す）)
    private func loadPastEvents(
        fromDayKey: Int,
        limit: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Int) {
        // 確実にlimit件取得するため、ループで繰り返し取得
        var fetchLimit = limit * 20
        let maxFetchLimit = limit * 200 // 最大でlimitの200倍まで取得を試みる
        var filtered: [ArchivedCalendarEvent] = []
        var reachedEnd = false

        while filtered.count < limit && fetchLimit <= maxFetchLimit {
            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey < fromDayKey
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.startDayKey, order: .reverse)]
            descriptor.fetchLimit = fetchLimit

            let allEvents = try modelContext.fetch(descriptor)
            let allEventsCount = allEvents.count

            // デバッグログ
            if filtered.isEmpty {
                print("📊 過去イベントロード: fromDayKey=\(fromDayKey), fetchLimit=\(fetchLimit), 取得件数=\(allEventsCount), 有効カレンダー数=\(enabledCalendarIds.count)")
                if allEventsCount > 0 {
                    let sampleCalendarIds = Set(allEvents.prefix(10).map { $0.calendarId })
                    print("📊 サンプルカレンダーID: \(sampleCalendarIds)")
                    print("📊 有効カレンダーID: \(enabledCalendarIds)")
                }
            }

            // 有効なカレンダーのイベントのみをフィルタ
            filtered = allEvents.filter { enabledCalendarIds.contains($0.calendarId) }

            // これ以上データがない場合は終了
            if allEventsCount < fetchLimit {
                print("📊 過去イベントロード完了: フィルタ後件数=\(filtered.count), これ以上データなし")
                reachedEnd = true
                break
            }

            // まだ足りない場合はfetchLimitを2倍にして再試行
            if filtered.count < limit {
                print("📊 過去イベント不足: フィルタ後件数=\(filtered.count), 目標=\(limit), fetchLimitを増加")
                fetchLimit *= 2
            }
        }

        print("📊 過去イベントロード最終結果: フィルタ後件数=\(filtered.count), reachedEnd=\(reachedEnd)")

        // limit件までに制限して返す
        // 戻り値: フィルタ後の件数を返す（これがlimit未満かつreachedEnd=trueなら、これ以上データがない）
        let result = Array(filtered.prefix(limit))
        return (result, result.count)
    }

    /// 未来方向のイベントをロード（startDayKey >= fromDayKey の範囲で昇順に limit 件）
    /// 戻り値: (フィルタ後のイベント, フィルタ後の件数（これがlimit未満なら、これ以上データがないことを示す）)
    private func loadFutureEvents(
        fromDayKey: Int,
        limit: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Int) {
        // 確実にlimit件取得するため、ループで繰り返し取得
        var fetchLimit = limit * 20
        let maxFetchLimit = limit * 200 // 最大でlimitの200倍まで取得を試みる
        var filtered: [ArchivedCalendarEvent] = []
        var reachedEnd = false

        while filtered.count < limit && fetchLimit <= maxFetchLimit {
            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey >= fromDayKey
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.startDayKey, order: .forward)]
            descriptor.fetchLimit = fetchLimit

            let allEvents = try modelContext.fetch(descriptor)
            let allEventsCount = allEvents.count

            // デバッグログ（初回のみ）
            if filtered.isEmpty && allEventsCount > 0 {
                print("📊 未来イベントロード: fromDayKey=\(fromDayKey), fetchLimit=\(fetchLimit), 取得件数=\(allEventsCount), 有効カレンダー数=\(enabledCalendarIds.count)")
            }

            // 有効なカレンダーのイベントのみをフィルタ
            filtered = allEvents.filter { enabledCalendarIds.contains($0.calendarId) }

            // これ以上データがない場合は終了
            if allEventsCount < fetchLimit {
                print("📊 未来イベントロード完了: フィルタ後件数=\(filtered.count), これ以上データなし")
                reachedEnd = true
                break
            }

            // まだ足りない場合はfetchLimitを2倍にして再試行
            if filtered.count < limit {
                print("📊 未来イベント不足: フィルタ後件数=\(filtered.count), 目標=\(limit), fetchLimitを増加")
                fetchLimit *= 2
            }
        }

        print("📊 未来イベントロード最終結果: フィルタ後件数=\(filtered.count), reachedEnd=\(reachedEnd)")

        // limit件までに制限して返す
        // 戻り値: フィルタ後の件数を返す（これがlimit未満かつreachedEnd=trueなら、これ以上データがない）
        let result = Array(filtered.prefix(limit))
        return (result, result.count)
    }

    /// 指定された日付の前後のイベントをロード（ジャーナルの日付範囲用）
    /// 戻り値: (フィルタ後のイベント, フィルタ前の件数)
    private func loadEventsAroundDate(
        dayKey: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Int) {
        // 前後50件ずつロード
        let halfRange = 50

        // 過去側
        let (pastEvents, pastCount) = try await loadPastEvents(
            fromDayKey: dayKey,
            limit: halfRange,
            modelContext: modelContext,
            enabledCalendarIds: enabledCalendarIds
        )

        // 未来側（指定日を含む）
        let (futureEvents, futureCount) = try await loadFutureEvents(
            fromDayKey: dayKey,
            limit: halfRange,
            modelContext: modelContext,
            enabledCalendarIds: enabledCalendarIds
        )

        let combined = pastEvents + futureEvents
        let totalCount = pastCount + futureCount

        return (combined, totalCount)
    }

    /// 指定された日付キーより前のデータが存在するか確認（より広い範囲で）
    private func checkIfMoreDataExists(
        beforeDayKey: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> Bool {
        // より広い範囲で確認（limitの5倍）
        let checkLimit = AppConfig.Timeline.pageSize * 5
        let predicate = #Predicate<ArchivedCalendarEvent> { event in
            event.startDayKey < beforeDayKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.startDayKey, order: .reverse)]
        descriptor.fetchLimit = checkLimit

        let allEvents = try modelContext.fetch(descriptor)

        // 有効なカレンダーのイベントが存在するか確認
        let hasEnabledEvents = allEvents.contains { enabledCalendarIds.contains($0.calendarId) }

        print("📊 広範囲チェック: 取得件数=\(allEvents.count), 有効イベント存在=\(hasEnabledEvents)")

        return hasEnabledEvents
    }

    /// アーカイブイベントの日付範囲（最小・最大のstartDayKey）を取得
    private func findArchivedEventDateRange(
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> (min: Int?, max: Int?) {
        // 有効なカレンダーのイベントのみを対象
        var descriptor = FetchDescriptor<ArchivedCalendarEvent>()
        descriptor.sortBy = [SortDescriptor(\.startDayKey, order: .forward)]

        let allEvents = try modelContext.fetch(descriptor)

        // 有効なカレンダーのイベントのみをフィルタ
        let enabledEvents = allEvents.filter { enabledCalendarIds.contains($0.calendarId) }

        guard !enabledEvents.isEmpty else {
            print("📦 アーカイブイベントが見つかりません")
            return (min: nil, max: nil)
        }

        let minDayKey = enabledEvents.map { $0.startDayKey }.min()
        let maxDayKey = enabledEvents.map { $0.startDayKey }.max()

        print("📦 アーカイブイベントの日付範囲: min=\(minDayKey ?? 0), max=\(maxDayKey ?? 0), 件数=\(enabledEvents.count)")

        return (min: minDayKey, max: maxDayKey)
    }

    /// 日付からYYYYMMDD形式の整数キーを生成
    private func makeDayKey(from date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        if let year = components.year, let month = components.month, let day = components.day {
            return year * 10000 + month * 100 + day
        }
        return 0
    }

    /// スクロール方向
    enum ScrollDirection {
        case past    // 過去方向（下へスクロール）
        case future  // 未来方向（上へスクロール）
    }
}
