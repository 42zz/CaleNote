import SwiftUI
import SwiftData

struct JournalDetailView: View {
    let entry: JournalEntry
    @State private var isPresentingEditor = false
    @State private var isPresentingConflictResolution = false
    
    @Query private var calendars: [CachedCalendar]

    private var tags: [String] {
        TagExtractor.extract(from: entry.body)
    }

    private var displayColor: Color {
        Color(hex: entry.colorHex) ?? .blue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ヘッダー部分（アイコンと色）
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(displayColor.opacity(0.2))
                            .frame(width: 60, height: 60)

                        Image(systemName: entry.iconName)
                            .font(.title)
                            .foregroundStyle(displayColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）")
                            .font(.title2)
                            .bold()

                        Text(entry.eventDate, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // タグセクション
                if !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("タグ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text("#")
                                        .foregroundStyle(.secondary)
                                    Text(tag)
                                }
                                .font(.subheadline)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule()
                                        .fill(displayColor.opacity(0.15))
                                )
                            }
                        }
                    }
                }

                Divider()

                // 本文セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("本文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(entry.body)
                        .font(.body)
                        .textSelection(.enabled)
                }

                Divider()

                // メタデータセクション
                VStack(alignment: .leading, spacing: 12) {
                    Text("詳細情報")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(spacing: 10) {
                        MetadataRow(
                            icon: "clock",
                            label: "作成日時",
                            value: formatDateTime(entry.createdAt)
                        )

                        MetadataRow(
                            icon: "clock.arrow.circlepath",
                            label: "更新日時",
                            value: formatDateTime(entry.updatedAt)
                        )

                        if entry.linkedCalendarId != nil {
                            MetadataRow(
                                icon: "checkmark.circle.fill",
                                label: "同期状態",
                                value: "カレンダーと同期済み",
                                valueColor: .green
                            )
                        } else if entry.needsCalendarSync {
                            MetadataRow(
                                icon: "exclamationmark.circle.fill",
                                label: "同期状態",
                                value: "同期待ち",
                                valueColor: .orange
                            )
                        } else {
                            MetadataRow(
                                icon: "circle",
                                label: "同期状態",
                                value: "未同期"
                            )
                        }

                        if entry.hasConflict {
                            MetadataRow(
                                icon: "exclamationmark.triangle.fill",
                                label: "競合状態",
                                value: "解決が必要",
                                valueColor: .orange
                            )

                            Button {
                                isPresentingConflictResolution = true
                            } label: {
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                    Text("競合を解決")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }

                        if let calendarId = entry.linkedCalendarId {
                            let calendar = calendars.first(where: { $0.calendarId == calendarId })
                            MetadataRow(
                                icon: "calendar",
                                label: "カレンダー",
                                value: calendar?.summary ?? (calendarId == "primary" ? "プライマリ" : calendarId)
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isPresentingEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            JournalEditorView(entry: entry)
        }
        .sheet(isPresented: $isPresentingConflictResolution) {
            ConflictResolutionView(entry: entry)
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}

// メタデータ行のコンポーネント
private struct MetadataRow: View {
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
