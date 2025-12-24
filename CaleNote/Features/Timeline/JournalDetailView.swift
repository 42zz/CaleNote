import SwiftUI
import SwiftData

struct JournalDetailView: View {
    let entry: JournalEntry
    @State private var isPresentingEditor = false
    @State private var isPresentingConflictResolution = false
    
    @Query private var calendars: [CachedCalendar]

    private var tags: [String] {
        TagExtractionUtility.extractTags(from: entry.body)
    }

    private var displayColor: Color {
        // colorHexはエントリ固有、ただし空文字列やデフォルト値の場合はカレンダーの色を使用
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
        return Color(hex: colorHex) ?? .blue
    }

    // タグを除去した本文
    private var bodyWithoutTags: String {
        TagExtractionUtility.removeTags(from: entry.body)
    }
    
    private var syncStatus: DetailMetadataSection.SyncStatus {
        if entry.linkedCalendarId != nil {
            return .synced
        } else if entry.needsCalendarSync {
            return .pending
        } else {
            return .notSynced
        }
    }
    
    private var calendarName: String? {
        if let linkedCalendarId = entry.linkedCalendarId,
           let calendar = calendars.first(where: { $0.calendarId == linkedCalendarId }),
           !calendar.summary.isEmpty {
            return calendar.summary
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 統合ヘッダー（カード形式 - コンパクト化）
                DetailHeaderView(
                    title: entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）",
                    eventDate: entry.eventDate,
                    isAllDay: true,
                    endDate: nil,
                    displayColor: displayColor,
                    showColorBar: false
                )

                // 本文セクション（段落構造を視覚化、常に全文表示）
                DetailDescriptionSection(
                    text: bodyWithoutTags,
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
                    displayColor: displayColor
                )

                // 関連する過去セクション
                RelatedMemoriesSection(targetDate: entry.eventDate)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isPresentingEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                        Text("編集")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(displayColor)
                    )
                    .frame(minHeight: 44) // アクセシビリティ対応
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            JournalEditorView(entry: entry)
        }
        .sheet(isPresented: $isPresentingConflictResolution) {
            ConflictResolutionView(entry: entry)
        }
    }
}
