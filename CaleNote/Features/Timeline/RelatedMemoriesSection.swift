import SwiftUI
import SwiftData

// 状態機械：永久ローディング防止のため明示的な状態管理
enum RelatedMemoriesLoadState: Equatable {
    case idle
    case loading
    case loaded([RelatedMemoryItem])
    case empty
    case failed(String)

    static func == (lhs: RelatedMemoriesLoadState, rhs: RelatedMemoriesLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.empty, .empty):
            return true
        case let (.loaded(items1), .loaded(items2)):
            return items1.map { $0.event.uid } == items2.map { $0.event.uid }
        case let (.failed(msg1), .failed(msg2)):
            return msg1 == msg2
        default:
            return false
        }
    }
}

struct RelatedMemoriesSection: View {
    let targetDate: Date
    let enabledCalendarIds: Set<String>
    let hasArchivedEvents: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var loadState: RelatedMemoriesLoadState = .idle
    @State private var displayedCount: Int = 10 // 初期表示上限

    private let service = RelatedMemoryService()
    private let settings = RelatedMemorySettings.load()

    // task(id:)のための安定したキー
    private var loadKey: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        let dayKey = (components.year ?? 0) * 10000 + (components.month ?? 0) * 100 + (components.day ?? 0)
        let idsHash = enabledCalendarIds.sorted().joined(separator: ",").hashValue
        return "\(dayKey)_\(idsHash)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // セクションヘッダー
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.blue)
                Text("関連するエントリー")
                    .font(.headline)

                Spacer()

                if settings.hasAnyEnabled {
                    Text(settings.enabledConditionsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // loadStateに基づいた表示切り替え
            switch loadState {
            case .idle:
                // 初期状態（通常は即座にloadingに遷移するので表示されない）
                EmptyView()

            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)

            case .failed(let errorMessage):
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)

            case .empty:
                // 該当なし
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("関連する過去のエントリーは見つかりませんでした")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)

            case .loaded(let relatedItems):
                if relatedItems.isEmpty {
                    // 0件は正常系として明示的に表示
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("関連する過去のエントリーは見つかりませんでした")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 12)
                } else {
                    // 関連エントリー一覧（年でグルーピング）
                    displayLoadedItems(relatedItems)
                }
            }

            // 特殊状態の案内（loadStateとは独立）
            if !hasArchivedEvents {
                archiveNotImportedView
            } else if !settings.hasAnyEnabled {
                settingsDisabledView
            }
        }
        .task(id: loadKey) {
            await loadRelatedMemories()
        }
    }

    private func loadRelatedMemories() async {
        // 既にloading中なら新規ロード要求は捨てる（デバウンス）
        if case .loading = loadState {
            print("⚠️ RelatedMemories: 既にloading中のためスキップ")
            return
        }

        // 設定無効の場合は即座にempty（hasArchivedEventsチェックは削除 - 実際にfetchして判断）
        if !settings.hasAnyEnabled {
            loadState = .empty
            print("ℹ️ RelatedMemories: 設定無効 → empty")
            return
        }

        loadState = .loading
        print("🔍 RelatedMemories: 読み込み開始 loadKey=\(loadKey) enabledCalendarIds件数=\(enabledCalendarIds.count) hasArchivedEvents=\(hasArchivedEvents)")

        // deferで確実にloading状態を抜ける（永久ローディング防止）
        defer {
            if case .loading = loadState {
                loadState = .empty
                print("⚠️ RelatedMemories: defer発動 → loading抜け（empty）")
            }
        }

        do {
            let items = try service.findRelatedMemories(
                for: targetDate,
                settings: settings,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            print("📊 RelatedMemories: Service返却件数=\(items.count)")

            // Task.checkCancellation()でキャンセル検出
            try Task.checkCancellation()

            // enabledCalendarIds が空の場合はフィルタしない（全て表示）
            let filtered: [RelatedMemoryItem]
            if enabledCalendarIds.isEmpty {
                filtered = items
                print("📊 RelatedMemories: enabledCalendarIds空 → フィルタなし 件数=\(items.count)")
            } else {
                filtered = items.filter { enabledCalendarIds.contains($0.event.calendarId) }
                print("📊 RelatedMemories: フィルタ後件数=\(filtered.count) (元: \(items.count))")
            }

            if filtered.isEmpty {
                loadState = .empty
                print("✅ RelatedMemories: 0件 → empty")
            } else {
                loadState = .loaded(filtered)
                print("✅ RelatedMemories: 読み込み完了 件数=\(filtered.count)")
            }
        } catch is CancellationError {
            // タスクキャンセル時は前回の結果を維持（loading固定禁止）
            if case .loading = loadState {
                loadState = .idle
            }
            print("🚫 RelatedMemories: タスクキャンセル → 前回の状態を維持")
        } catch {
            loadState = .failed("関連メモリーの読み込みに失敗しました")
            print("❌ RelatedMemories: エラー \(error)")
        }
    }
    
    // 年でグルーピング（年をDateFormatterで文字列化）
    private func groupByYear(_ items: ArraySlice<RelatedMemoryItem>) -> [String: [RelatedMemoryItem]] {
        var grouped: [String: [RelatedMemoryItem]] = [:]
        let yearFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年"
            formatter.locale = Locale(identifier: "ja_JP")
            return formatter
        }()
        
        for item in items {
            let yearString = yearFormatter.string(from: item.event.start)
            if grouped[yearString] == nil {
                grouped[yearString] = []
            }
            grouped[yearString]?.append(item)
        }
        return grouped
    }
    
    // 年差を計算（targetDateとの差分）
    private func yearsDifference(from eventDate: Date) -> Int {
        let calendar = Calendar.current
        let targetYear = calendar.component(.year, from: targetDate)
        let eventYear = calendar.component(.year, from: eventDate)
        return eventYear - targetYear
    }

    // 年文字列から年数を抽出（ソート用）
    private func extractYear(from yearString: String) -> Int {
        // "2021年" から "2021" を抽出
        let cleaned = yearString.replacingOccurrences(of: "年", with: "")
        return Int(cleaned) ?? 0
    }

    // ロード済みアイテムの表示（年でグルーピング）
    @ViewBuilder
    private func displayLoadedItems(_ relatedItems: [RelatedMemoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let groupedItems = groupByYear(relatedItems.prefix(displayedCount))
            // 年を数値としてソート（降順：新しい年から）
            let sortedYears = groupedItems.keys.sorted { yearString1, yearString2 in
                let year1 = extractYear(from: yearString1)
                let year2 = extractYear(from: yearString2)
                return year1 > year2
            }
            ForEach(sortedYears, id: \.self) { yearString in
                VStack(alignment: .leading, spacing: 8) {
                    // 年ヘッダー（「2021年　4年前」形式）
                    if let firstItem = groupedItems[yearString]?.first {
                        let yearDiff = yearsDifference(from: firstItem.event.start)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(yearString)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if yearDiff != 0 {
                                Text(yearDiff < 0 ? "\(abs(yearDiff))年前" : "\(yearDiff)年後")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    // その年のエントリー
                    ForEach(groupedItems[yearString] ?? [], id: \.event.uid) { item in
                        RelatedMemoryRow(item: item)
                    }
                }
            }

            // 「さらに表示」ボタン
            if relatedItems.count > displayedCount {
                Button {
                    withAnimation {
                        displayedCount += 10
                    }
                } label: {
                    HStack {
                        Text("さらに表示")
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // 長期キャッシュ未取り込み案内
    private var archiveNotImportedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("過去のエントリーを表示するには、長期キャッシュの取り込みが必要です")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                SettingsView()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("設定画面で長期キャッシュを取り込む")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.subheadline)
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 12)
    }

    // 設定無効案内
    private var settingsDisabledView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("関連メモリーの条件が無効になっています")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("「同日」「同週同曜」「同祝日」のいずれかを有効にすると、過去のエントリーが表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                SettingsView()
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("設定画面で条件を有効化")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.subheadline)
                .padding()
                .background(Color.orange.opacity(0.1))
                .foregroundStyle(.orange)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Related Memory Row

private struct RelatedMemoryRow: View {
    let item: RelatedMemoryItem
    
    // 日付フォーマッター（終日用）
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    // 日時フォーマッター（時間指定用）
    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }

    var body: some View {
        NavigationLink {
            ArchivedCalendarEventDetailView(
                event: item.event,
                calendar: nil
            )
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // タイトル（階層1）
                Text(item.event.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                // 日付とラベル（階層2）
                HStack(spacing: 8) {
                    // 日付（必ず表示）
                    if item.event.isAllDay {
                        // 終日イベント: YYYY/MM/DDのみ
                        Text(dateFormatter.string(from: item.event.start))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // 時間指定イベント: YYYY/MM/DD  HH:mm
                        Text(dateTimeFormatter.string(from: item.event.start))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 一致理由バッジ（ラベル）
                    HStack(spacing: 4) {
                        ForEach(Array(item.matchReasons), id: \.self) { reason in
                            Text(reason.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.15))
                                .foregroundStyle(.secondary)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // 行全体をタップ可能に
        }
        .buttonStyle(.plain) // リンク色の強さを調整
    }
}
