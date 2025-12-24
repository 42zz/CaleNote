import SwiftData
import SwiftUI

struct CalendarEventDetailView: View {
    let event: CachedCalendarEvent
    let calendar: CachedCalendar?

    @Environment(\.modelContext) private var modelContext
    @Query private var cachedCalendars: [CachedCalendar]
    @State private var isPresentingEditor = false
    @State private var journalEntryForEdit: JournalEntry?

    // event.calendarIdから正しいカレンダーを取得
    private var correctCalendar: CachedCalendar? {
        cachedCalendars.first { $0.calendarId == event.calendarId }
    }

    private var displayColor: Color {
        if let hex = correctCalendar?.userColorHex {
            return Color(hex: hex) ?? .blue
        }
        return .blue
    }

    // タグを除去した説明文
    private var descriptionWithoutTags: String {
        guard let desc = event.desc, !desc.isEmpty else { return "" }
        var text = desc
        // タグパターンを除去
        let pattern = #"#([^\s#]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(
                in: text, options: [], range: range, withTemplate: "")
        }
        // 連続する空白を整理（改行は保持）
        let lines = text.components(separatedBy: "\n")
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // 説明文から抽出したタグ
    private var tags: [String] {
        guard let desc = event.desc, !desc.isEmpty else { return [] }
        let extracted = TagExtractor.extract(from: desc)
        // 重複除去と正規化
        var seen = Set<String>()
        var unique: [String] = []
        for tag in extracted {
            let normalized = tag.trimmingCharacters(in: .whitespaces).lowercased()
            if !normalized.isEmpty && !seen.contains(normalized) {
                seen.insert(normalized)
                unique.append(tag)  // 表示用には元のケースを保持
            }
        }
        return unique
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 統合ヘッダー（カード形式 - コンパクト化）
                VStack(alignment: .leading, spacing: 10) {
                    // タイトル（フォントサイズを一段落とす）
                    Text(event.title)
                        .font(.title2)
                        .bold()
                        .padding(.top, 6)

                    // 日時情報
                    VStack(alignment: .leading, spacing: 6) {
                        if event.isAllDay {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(displayColor.opacity(0.7))
                                    .font(.caption)
                                Text("終日")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatDate(event.start))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text("開始")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(formatTime(event.start))
                                            .font(.caption)
                                            .bold()
                                    }
                                    Text(formatDateOnly(event.start))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let end = event.end {
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 4) {
                                            Text("終了")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(formatTime(end))
                                                .font(.caption)
                                                .bold()
                                        }
                                        Text(formatDateOnly(end))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .background(Color(UIColor.tertiarySystemBackground).opacity(0.5))
                .cornerRadius(10)

                // 説明セクション（本文 - 段落構造を視覚化、常に全文表示）
                if !descriptionWithoutTags.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        // 全文表示（タグ除去済み）
                        ParagraphTextView(text: descriptionWithoutTags)

                        // タグセクション（本文の最後に小さめに表示）
                        if !tags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("タグ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 3) {
                                            Text("#")
                                                .foregroundStyle(.secondary)
                                            Text(tag)
                                        }
                                        .font(.caption)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(
                                            Capsule()
                                                .fill(displayColor.opacity(0.1))
                                        )
                                    }
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // メタ情報（カレンダー所属・同期状態）- 関連エントリー直前に配置
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // カレンダー所属（色ドット＋カレンダー名）
                        if let calendar = correctCalendar, !calendar.summary.isEmpty {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(displayColor)
                                    .frame(width: 6, height: 6)
                                Text(calendar.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 同期状態
                        if event.status == "confirmed" && !event.eventId.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                Text("Googleカレンダーと同期済み")
                                    .font(.caption)
                            }
                            .foregroundStyle(.green)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 4)

                // 関連する過去セクション
                RelatedMemoriesSection(targetDate: event.start)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: prepareEditJournal) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text("編集")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(displayColor))
                }
                .buttonStyle(.borderless)  // plainよりborderlessの方が効くことがある
                .tint(.clear)  // Toolbarの「色付きボタン化」を抑止
            }
        }

        .sheet(isPresented: $isPresentingEditor) {
            if let entry = journalEntryForEdit {
                JournalEditorView(entry: entry)
            }
        }
    }

    private func prepareEditJournal() {
        // 既存のジャーナルを取得または新規作成
        if let journalIdString = event.linkedJournalId,
            let uuid = UUID(uuidString: journalIdString)
        {
            // 紐づいているジャーナルを取得
            let predicate = #Predicate<JournalEntry> { $0.id == uuid }
            let descriptor = FetchDescriptor(predicate: predicate)
            if let existingEntry = try? modelContext.fetch(descriptor).first {
                journalEntryForEdit = existingEntry
                isPresentingEditor = true
                return
            }
        }

        // 紐づいているジャーナルがない場合は新規作成
        // カレンダーの色とアイコンを取得
        let calendarColorHex = correctCalendar?.userColorHex ?? "#3B82F6"
        let calendarIconName = correctCalendar?.iconName ?? "calendar"

        let newEntry = JournalEntry(
            title: event.title.isEmpty ? nil : event.title,
            body: event.desc ?? "",
            eventDate: event.start,
            colorHex: calendarColorHex,
            iconName: calendarIconName,
            linkedCalendarId: event.calendarId,
            linkedEventId: event.eventId,
            linkedEventUpdatedAt: event.updatedAt,
            needsCalendarSync: false
        )
        modelContext.insert(newEntry)
        try? modelContext.save()

        // カレンダーイベント側にもリンクを設定
        event.linkedJournalId = newEntry.id.uuidString
        try? modelContext.save()

        journalEntryForEdit = newEntry
        isPresentingEditor = true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

// 段落構造を視覚化するテキストビュー
private struct ParagraphTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var paragraphs: [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// フローレイアウト（タグを折り返し表示するため）
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
