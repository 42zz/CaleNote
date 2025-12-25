import SwiftUI
import SwiftData

struct JournalDetailView: View {
    let entry: JournalEntry
    @State private var isPresentingEditor = false
    @State private var isPresentingConflictResolution = false

    @Query private var calendars: [CachedCalendar]

    @State private var enabledCalendarIds: Set<String> = []
    @State private var hasArchivedEvents = false
    @State private var tags: [String] = []
    @State private var bodyWithoutTagsCache: String = ""

    // キャッシュ化されたcomputed properties（body再評価で毎回計算しない）
    @State private var displayColor: Color = .blue
    @State private var syncStatus: DetailMetadataSection.SyncStatus = .notSynced
    @State private var calendarName: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 統合ヘッダー（カード形式 - コンパクト化）
                DetailHeaderView(
                    title: entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）",
                    displayColor: displayColor,
                    showColorBar: false
                )

                // 本文セクション（段落構造を視覚化、常に全文表示）
                DetailDescriptionSection(
                    text: bodyWithoutTagsCache,
                    tags: tags,
                    displayColor: displayColor
                )

                // 競合状態（重要な場合は目立つように）
                if entry.hasConflict {
                    Button {
                        isPresentingConflictResolution = true
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("競合を解決")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 4)
                }

                // メタ情報（カレンダー所属・同期状態）- 関連エントリー直前に配置
                DetailMetadataSection(
                    calendarName: calendarName,
                    syncStatus: syncStatus,
                    displayColor: displayColor,
                    lastSyncedAt: (syncStatus == .synced) ? entry.updatedAt : nil
                )

                // 関連する過去セクション
                RelatedMemoriesSection(
                    targetDate: entry.eventDate,
                    enabledCalendarIds: enabledCalendarIds,
                    hasArchivedEvents: hasArchivedEvents
                )
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            // enabledCalendarIds の初期化を最優先で実行（RelatedMemoriesSection が依存するため）
            updateEnabledCalendarIds()
            // 重い処理は Task 内で実行
            updateCachedData()
        }
        .onChange(of: calendars) { _, _ in
            // カレンダーリスト変更時は即座に更新
            updateEnabledCalendarIds()
        }
        .onChange(of: entry.body) { _, _ in
            // 本文変更時のみキャッシュ更新
            updateCachedData()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationDateTimeView(
                    eventDate: entry.eventDate,
                    isAllDay: true,
                    endDate: nil,
                    displayColor: displayColor
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isPresentingEditor = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text("編集")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.blue)
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            JournalEditorView(entry: entry)
        }
        .sheet(isPresented: $isPresentingConflictResolution) {
            ConflictResolutionView(entry: entry)
        }
    }

    private func updateEnabledCalendarIds() {
        let newIds = Set(calendars.filter { $0.isEnabled }.map { $0.calendarId })
        // 差分がある場合のみ更新
        if newIds != enabledCalendarIds {
            enabledCalendarIds = newIds
            print("📝 JournalDetailView: enabledCalendarIds更新 件数=\(newIds.count)")
        }
    }

    private func updateCachedData() {
        // 重い処理をTask内で実行してメインスレッドブロックを防ぐ
        Task { @MainActor in
            // タグ抽出（@Stateにキャッシュして毎回計算しない）
            let newTags = TagExtractionUtility.extractTags(from: entry.body)
            if newTags != tags {
                tags = newTags
            }

            // タグ除去済み本文（@Stateにキャッシュして毎回計算しない）
            let newBodyWithoutTags = TagExtractionUtility.removeTags(from: entry.body)
            if newBodyWithoutTags != bodyWithoutTagsCache {
                bodyWithoutTagsCache = newBodyWithoutTags
            }

            // displayColor計算（body評価で毎回first(where:)しない）
            let colorHex: String
            if entry.colorHex.isEmpty || entry.colorHex == "#3B82F6" {
                // カレンダーの色を使用
                if let linkedCalendarId = entry.linkedCalendarId,
                   let calendar = calendars.first(where: { $0.calendarId == linkedCalendarId }),
                   !calendar.userColorHex.isEmpty {
                    colorHex = calendar.userColorHex
                } else {
                    colorHex = "#3B82F6"
                }
            } else {
                colorHex = entry.colorHex
            }
            displayColor = Color(hex: colorHex) ?? .blue

            // syncStatus計算
            if entry.linkedCalendarId != nil {
                syncStatus = .synced
            } else if entry.needsCalendarSync {
                syncStatus = .pending
            } else {
                syncStatus = .notSynced
            }

            // calendarName計算（body評価で毎回first(where:)しない）
            if let linkedCalendarId = entry.linkedCalendarId,
               let calendar = calendars.first(where: { $0.calendarId == linkedCalendarId }),
               !calendar.summary.isEmpty {
                calendarName = calendar.summary
            } else {
                calendarName = nil
            }

            // hasArchivedEventsの確認（軽量なカウントクエリ）
            let descriptor = FetchDescriptor<ArchivedCalendarEvent>()
            if let count = try? calendars.first?.modelContext?.fetchCount(descriptor), count > 0 {
                hasArchivedEvents = true
            } else {
                hasArchivedEvents = false
            }
        }
    }
}
