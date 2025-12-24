import Foundation
import SwiftUI

// MARK: - DateTime Component

struct DetailDateTimeView: View {
    let eventDate: Date
    let isAllDay: Bool
    let endDate: Date?
    let displayColor: Color

    init(
        eventDate: Date,
        isAllDay: Bool,
        endDate: Date? = nil,
        displayColor: Color
    ) {
        self.eventDate = eventDate
        self.isAllDay = isAllDay
        self.endDate = endDate
        self.displayColor = displayColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isAllDay {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(displayColor.opacity(0.7))
                        .font(.caption)
                    Text(DetailViewDateFormatter.formatDate(eventDate))
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
                            Text(DetailViewDateFormatter.formatTime(eventDate))
                                .font(.caption)
                        }
                        Text(DetailViewDateFormatter.formatDateOnly(eventDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let end = endDate {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text("終了")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(DetailViewDateFormatter.formatTime(end))
                                    .font(.caption)
                            }
                            Text(DetailViewDateFormatter.formatDateOnly(end))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Navigation Title DateTime Component

struct NavigationDateTimeView: View {
    let eventDate: Date
    let isAllDay: Bool
    let endDate: Date?
    let displayColor: Color

    init(
        eventDate: Date,
        isAllDay: Bool,
        endDate: Date? = nil,
        displayColor: Color
    ) {
        self.eventDate = eventDate
        self.isAllDay = isAllDay
        self.endDate = endDate
        self.displayColor = displayColor
    }

    var body: some View {
        VStack(spacing: 2) {
            if isAllDay {
                HStack(spacing: 4) {
                    Text(DetailViewDateFormatter.formatDate(eventDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(DetailViewDateFormatter.formatDateOnly(eventDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(DetailViewDateFormatter.formatTime(eventDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let end = endDate {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(DetailViewDateFormatter.formatTime(end))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Header Component

struct DetailHeaderView: View {
    let title: String
    let displayColor: Color
    let showColorBar: Bool

    init(
        title: String,
        displayColor: Color,
        showColorBar: Bool = false
    ) {
        self.title = title
        self.displayColor = displayColor
        self.showColorBar = showColorBar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showColorBar {
                Rectangle()
                    .fill(displayColor)
                    .frame(height: 3)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title2)
                    .bold()
                    .padding(.horizontal, showColorBar ? 16 : 0)
                    .padding(.top, showColorBar ? 12 : (showColorBar ? 0 : 6))
            }
            .background(Color(UIColor.tertiarySystemBackground).opacity(0.5))
            .cornerRadius(10)
        }
    }
}

// MARK: - Description Section Component

struct DetailDescriptionSection: View {
    let text: String
    let tags: [String]
    let displayColor: Color

    var body: some View {
        // テキストまたはタグのいずれかがあれば表示
        if !text.isEmpty || !tags.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if !text.isEmpty {
                    ParagraphTextView(text: text)
                }

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
                    .padding(.top, text.isEmpty ? 0 : 12)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Metadata Section Component

struct DetailMetadataSection: View {
    let calendarName: String?
    let syncStatus: SyncStatus
    let displayColor: Color
    let lastSyncedAt: Date?
    let additionalMetadata: [AdditionalMetadataItem]

    enum SyncStatus {
        case synced
        case pending
        case notSynced
        case none
    }

    struct AdditionalMetadataItem {
        let icon: String
        let label: String
        let value: String
        var valueColor: Color = .primary

        init(icon: String, label: String, value: String, valueColor: Color = .primary) {
            self.icon = icon
            self.label = label
            self.value = value
            self.valueColor = valueColor
        }
    }

    init(
        calendarName: String?,
        syncStatus: SyncStatus,
        displayColor: Color,
        lastSyncedAt: Date? = nil,
        additionalMetadata: [AdditionalMetadataItem] = []
    ) {
        self.calendarName = calendarName
        self.syncStatus = syncStatus
        self.displayColor = displayColor
        self.lastSyncedAt = lastSyncedAt
        self.additionalMetadata = additionalMetadata
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 基本メタ情報（カレンダー名・同期状態）
            HStack(spacing: 12) {
                // カレンダー所属（色ドット＋カレンダー名）
                if let calendarName = calendarName, !calendarName.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(displayColor)
                            .frame(width: 6, height: 6)
                        Text(calendarName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 同期状態
                switch syncStatus {
                case .synced:
                    if let lastSyncedAt = lastSyncedAt {
                        HStack(spacing: 4) {
                            Text("最終同期:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(DetailViewDateFormatter.formatSyncDateTime(lastSyncedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        EmptyView()
                    }
                case .pending:
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text("同期待ち")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                case .notSynced:
                    HStack(spacing: 4) {
                        Image(systemName: "circle")
                            .font(.caption2)
                        Text("未同期")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                case .none:
                    EmptyView()
                }

                Spacer()
            }

            // 追加メタデータ（アーカイブイベントなどで使用）
            if !additionalMetadata.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(additionalMetadata.enumerated()), id: \.offset) { _, item in
                        MetadataRow(
                            icon: item.icon,
                            label: item.label,
                            value: item.value,
                            valueColor: item.valueColor
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Metadata Row Component (for detailed metadata)

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)

            Spacer()
        }
    }
}

// MARK: - Paragraph Text View

struct ParagraphTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paragraphs, id: \.self) { paragraph in
                // URLを自動リンク化したAttributedStringを使用
                Text(URLLinkifierUtility.linkify(paragraph))
                    .font(.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .tint(.blue)  // リンク色をOS標準の青に設定
            }
        }
    }

    private var paragraphs: [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
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

// MARK: - Tag Extraction Utility

struct TagExtractionUtility {
    static func extractTags(from text: String) -> [String] {
        let extracted = TagExtractor.extract(from: text)
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

    static func removeTags(from text: String) -> String {
        var text = text
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
}

// MARK: - URL Linkifier Utility

struct URLLinkifierUtility {
    /// テキスト内のURLを検出してリンク属性を付与したAttributedStringを返す
    /// - Parameter text: 元のテキスト
    /// - Returns: URLがリンク化されたAttributedString
    static func linkify(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)

        // NSDataDetectorでURL検出
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributedString
        }

        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = detector.matches(in: text, options: [], range: range)

        // マッチしたURLに対してリンク属性を設定（逆順で処理して範囲の整合性を保つ）
        for match in matches.reversed() {
            guard let url = match.url else { continue }

            // NSRangeをSwift Stringのインデックスに変換
            if let range = Range(match.range, in: text) {
                // AttributedStringのrangeに変換
                if let attributedRange = Range(range, in: attributedString) {
                    attributedString[attributedRange].link = url
                }
            }
        }

        return attributedString
    }
}
