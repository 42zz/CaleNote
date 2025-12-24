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

            // より広い範囲を初期ロードで取得（中間の日付が抜けないように）
            let wideInitialPageSize = AppConfig.Timeline.maxLoadedItems // 600件

            // 1. 今日を中心に未来側をロード（今日を含む）
            let (futureEvents, futureBeforeFilterCount) = try await loadFutureEvents(
                fromDayKey: todayKey,
                limit: wideInitialPageSize / 2, // 300件
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            allLoadedEvents.append(contentsOf: futureEvents)

            // 2. 今日を中心に過去側をロード（今日は含まない）
            let (pastEvents, pastBeforeFilterCount) = try await loadPastEvents(
                fromDayKey: todayKey - 1,  // 今日の前日から
                limit: wideInitialPageSize / 2, // 300件
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            allLoadedEvents.append(contentsOf: pastEvents)

            // 3. ジャーナルの日付範囲も追加でロード（常にロードして確実性を高める）
            if let dateRange = journalDateRange {
                print("📓 ジャーナルの日付範囲を追加ロード: min=\(dateRange.min?.description ?? "nil"), max=\(dateRange.max?.description ?? "nil")")

                // ジャーナルの最小日付より前のデータをロード（常にロード）
                if let minDate = dateRange.min {
                    let minDayKey = makeDayKey(from: minDate)
                    print("📓 ジャーナルの最小日付周辺をロード: \(minDayKey)")
                    let (journalPastEvents, _) = try await loadEventsAroundDate(
                        dayKey: minDayKey,
                        modelContext: modelContext,
                        enabledCalendarIds: enabledCalendarIds
                    )
                    print("📓 ジャーナル最小日付周辺のイベント数: \(journalPastEvents.count)")
                    allLoadedEvents.append(contentsOf: journalPastEvents)
                }

                // ジャーナルの最大日付より後のデータをロード（常にロード）
                if let maxDate = dateRange.max {
                    let maxDayKey = makeDayKey(from: maxDate)
                    print("📓 ジャーナルの最大日付周辺をロード: \(maxDayKey)")
                    let (journalFutureEvents, _) = try await loadEventsAroundDate(
                        dayKey: maxDayKey,
                        modelContext: modelContext,
                        enabledCalendarIds: enabledCalendarIds
                    )
                    print("📓 ジャーナル最大日付周辺のイベント数: \(journalFutureEvents.count)")
                    allLoadedEvents.append(contentsOf: journalFutureEvents)
                }
            }

            // 4. アーカイブイベントの日付範囲も追加でロード（常にロードして確実性を高める）
            // （ジャーナルに紐づかない古いイベントも表示するため）
            let archiveDateRange = try await findArchivedEventDateRange(
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            if let archiveMin = archiveDateRange.min {
                let archiveMinDayKey = archiveMin
                print("📦 アーカイブの最小日付周辺をロード: \(archiveMinDayKey)")
                let (archivePastEvents, _) = try await loadEventsAroundDate(
                    dayKey: archiveMinDayKey,
                    modelContext: modelContext,
                    enabledCalendarIds: enabledCalendarIds
                )
                print("📦 アーカイブ最小日付周辺のイベント数: \(archivePastEvents.count)")
                allLoadedEvents.append(contentsOf: archivePastEvents)
            }

            if let archiveMax = archiveDateRange.max {
                let archiveMaxDayKey = archiveMax
                print("📦 アーカイブの最大日付周辺をロード: \(archiveMaxDayKey)")
                let (archiveFutureEvents, _) = try await loadEventsAroundDate(
                    dayKey: archiveMaxDayKey,
                    modelContext: modelContext,
                    enabledCalendarIds: enabledCalendarIds
                )
                print("📦 アーカイブ最大日付周辺のイベント数: \(archiveFutureEvents.count)")
                allLoadedEvents.append(contentsOf: archiveFutureEvents)
            }

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

            // データがない場合は到達フラグを立てる
            // フィルタリング前の件数も確認して、実際にデータベースにデータがない場合のみ到達とみなす
            if futureBeforeFilterCount < AppConfig.Timeline.initialPageSize {
                hasReachedLatestData = true
            }
            // フィルタリング前の件数がlimit未満の場合のみ、これ以上データがないと判断
            if pastBeforeFilterCount < AppConfig.Timeline.initialPageSize {
                hasReachedEarliestData = true
            }

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
            let (newEvents, beforeFilterCount) = try await loadPastEvents(
                fromDayKey: currentEarliest - 1,
                limit: AppConfig.Timeline.pageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            print("📄 過去ページロード結果: 新規イベント数=\(newEvents.count), フィルタ前件数=\(beforeFilterCount), limit=\(AppConfig.Timeline.pageSize)")

            // フィルタリング前の件数がlimit未満の場合のみ、これ以上データがないと判断
            // ただし、データベースにデータが存在する可能性があるため、より広い範囲で確認
            if beforeFilterCount < AppConfig.Timeline.pageSize {
                // データベースにデータが存在するか、より広い範囲で確認
                let widerCheck = try? await checkIfMoreDataExists(
                    beforeDayKey: currentEarliest - 1,
                    modelContext: modelContext,
                    enabledCalendarIds: enabledCalendarIds
                )
                
                if let hasMore = widerCheck, !hasMore {
                    print("📄 過去データの最後に到達: beforeFilterCount(\(beforeFilterCount)) < limit(\(AppConfig.Timeline.pageSize)), 広範囲チェックでもデータなし")
                    hasReachedEarliestData = true
                } else if beforeFilterCount == 0 {
                    // データベースにデータが存在しない場合
                    print("📄 過去データの最後に到達: データベースにデータが存在しない")
                    hasReachedEarliestData = true
                } else {
                    print("📄 フィルタリングで空になったが、データベースにはデータが存在する可能性がある")
                }
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
            let (newEvents, beforeFilterCount) = try await loadFutureEvents(
                fromDayKey: currentLatest + 1,
                limit: AppConfig.Timeline.pageSize,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            // フィルタリング前の件数がlimit未満の場合のみ、これ以上データがないと判断
            // （フィルタリングで空になった可能性があるため、フィルタ後の件数だけでは判断しない）
            if beforeFilterCount < AppConfig.Timeline.pageSize {
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
    /// 戻り値: (フィルタ後のイベント, フィルタ前の件数)
    private func loadPastEvents(
        fromDayKey: Int,
        limit: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Int) {
        let predicate = #Predicate<ArchivedCalendarEvent> { event in
            event.startDayKey < fromDayKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.startDayKey, order: .reverse)]
        // フィルタリングで空になる可能性を考慮して、かなり多めに取得
        // 有効なカレンダーのイベントが少数の場合でも確実に取得できるよう、大きめの倍率を使用
        descriptor.fetchLimit = limit * 20

        let allEvents = try modelContext.fetch(descriptor)
        let beforeFilterCount = allEvents.count

        // デバッグログ
        print("📊 過去イベントロード: fromDayKey=\(fromDayKey), 取得件数=\(beforeFilterCount), 有効カレンダー数=\(enabledCalendarIds.count)")
        if beforeFilterCount > 0 {
            let sampleCalendarIds = Set(allEvents.prefix(10).map { $0.calendarId })
            print("📊 サンプルカレンダーID: \(sampleCalendarIds)")
            print("📊 有効カレンダーID: \(enabledCalendarIds)")
        }

        // 有効なカレンダーのイベントのみをフィルタ
        let filtered = allEvents.filter { enabledCalendarIds.contains($0.calendarId) }

        print("📊 フィルタ後件数: \(filtered.count)")

        // limit件までに制限
        return (Array(filtered.prefix(limit)), beforeFilterCount)
    }

    /// 未来方向のイベントをロード（startDayKey >= fromDayKey の範囲で昇順に limit 件）
    /// 戻り値: (フィルタ後のイベント, フィルタ前の件数)
    private func loadFutureEvents(
        fromDayKey: Int,
        limit: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) async throws -> ([ArchivedCalendarEvent], Int) {
        let predicate = #Predicate<ArchivedCalendarEvent> { event in
            event.startDayKey >= fromDayKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.startDayKey, order: .forward)]
        // フィルタリングで空になる可能性を考慮して、かなり多めに取得
        // 有効なカレンダーのイベントが少数の場合でも確実に取得できるよう、大きめの倍率を使用
        descriptor.fetchLimit = limit * 20

        let allEvents = try modelContext.fetch(descriptor)
        let beforeFilterCount = allEvents.count

        // 有効なカレンダーのイベントのみをフィルタ
        let filtered = allEvents.filter { enabledCalendarIds.contains($0.calendarId) }

        // limit件までに制限
        return (Array(filtered.prefix(limit)), beforeFilterCount)
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
