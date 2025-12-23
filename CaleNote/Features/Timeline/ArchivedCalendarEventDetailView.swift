import SwiftUI
import SwiftData

struct ArchivedCalendarEventDetailView: View {
    let event: ArchivedCalendarEvent
    let calendar: CachedCalendar?

    private var displayColor: Color {
        if let hex = calendar?.userColorHex {
            return Color(hex: hex) ?? .blue
        }
        return .blue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ヘッダー部分
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(displayColor.opacity(0.2))
                            .frame(width: 60, height: 60)

                        Image(systemName: "archivebox")
                            .font(.title)
                            .foregroundStyle(displayColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.title2)
                            .bold()

                        if event.isAllDay {
                            Text("終日")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(event.start, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                // アーカイブ表示のバッジ
                // HStack {
                //     Label("長期キャッシュ", systemImage: "archivebox.fill")
                //         .font(.caption)
                //         .foregroundStyle(.secondary)
                //         .padding(.horizontal, 8)
                //         .padding(.vertical, 4)
                //         .background(Color.secondary.opacity(0.1))
                //         .cornerRadius(8)
                // }

                // 日時セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("日時")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 4) {
                        if event.isAllDay {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                Text(formatDate(event.start))
                            }
                        } else {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                if let end = event.end {
                                    Text("\(formatDateTime(event.start)) 〜 \(formatDateTime(end))")
                                } else {
                                    Text(formatDateTime(event.start))
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }

                // 説明セクション
                if let desc = event.desc, !desc.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("説明")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(desc)
                            .font(.body)
                            .textSelection(.enabled)
                    }
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
                            icon: "calendar.badge.clock",
                            label: "カレンダー",
                            value: calendar?.summary ?? event.calendarId
                        )

                        MetadataRow(
                            icon: "info.circle",
                            label: "ステータス",
                            value: event.status
                        )

                        if event.linkedJournalId != nil {
                            MetadataRow(
                                icon: "link.circle.fill",
                                label: "連携",
                                value: "ジャーナルと連携済み",
                                valueColor: .blue
                            )
                        }

                        MetadataRow(
                            icon: "clock.arrow.circlepath",
                            label: "キャッシュ日時",
                            value: formatDateTime(event.cachedAt)
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle("カレンダーイベント")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
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

