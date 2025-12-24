import SwiftUI
import SwiftData

struct JournalDetailView: View {
    let entry: JournalEntry
    @State private var isPresentingEditor = false
    @State private var isPresentingConflictResolution = false
    
    @Query private var calendars: [CachedCalendar]

    private var tags: [String] {
        let extracted = TagExtractor.extract(from: entry.body)
        // 重複除去と正規化
        var seen = Set<String>()
        var unique: [String] = []
        for tag in extracted {
            let normalized = tag.trimmingCharacters(in: .whitespaces).lowercased()
            if !normalized.isEmpty && !seen.contains(normalized) {
                seen.insert(normalized)
                unique.append(tag) // 表示用には元のケースを保持
            }
        }
        return unique
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
        var text = entry.body
        // タグパターンを除去
        let pattern = #"#([^\s#]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        // 連続する空白を整理（改行は保持）
        let lines = text.components(separatedBy: "\n")
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 統合ヘッダー（カード形式 - コンパクト化）
                VStack(alignment: .leading, spacing: 0) {
                    // カラーバー（上部 - 所属カレンダー色として意味付け）
                    Rectangle()
                        .fill(displayColor)
                        .frame(height: 3)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // タイトル（フォントサイズを一段落とす）
                        Text(entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        
                        // 日付情報
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundStyle(displayColor.opacity(0.7))
                                .font(.caption)
                            Text(entry.eventDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .background(Color(UIColor.tertiarySystemBackground).opacity(0.5))
                    .cornerRadius(10)
                }

                // 本文セクション（段落構造を視覚化、常に全文表示）
                VStack(alignment: .leading, spacing: 16) {
                    // 全文表示（タグ除去済み）
                    ParagraphTextView(text: bodyWithoutTags)
                    
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // カレンダー所属（色ドット＋カレンダー名）
                        if let calendarId = entry.linkedCalendarId,
                           let calendar = calendars.first(where: { $0.calendarId == calendarId }),
                           !calendar.summary.isEmpty {
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
                        if entry.linkedCalendarId != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                Text("Googleカレンダーと同期済み")
                                    .font(.caption)
                            }
                            .foregroundStyle(.green)
                        } else if entry.needsCalendarSync {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                Text("同期待ち")
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "circle")
                                    .font(.caption2)
                                Text("未同期")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)

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

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
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

// Color拡張（16進数からColorを生成）
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
