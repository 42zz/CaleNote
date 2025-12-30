import Combine
import SwiftData
import SwiftUI

struct TagsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var searchIndex: SearchIndexService

    @AppStorage("timelineShowTags") private var showTags = true

    @State private var selectedTags: Set<String> = []
    @State private var matchMode: TagMatchMode = .all

    private var tagSummaries: [SearchIndexService.TagSummary] {
        searchIndex.tagSummaries()
    }

    private var recentTags: [SearchIndexService.TagSummary] {
        searchIndex.recentTags(limit: 8)
    }

    private var filteredEntries: [ScheduleEntry] {
        searchIndex.entries(matching: Array(selectedTags), matchAll: matchMode == .all)
    }

    var body: some View {
        List {
            Section("最近使ったタグ") {
                if recentTags.isEmpty {
                    Text("最近使ったタグはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentTags) { tag in
                                TagChip(
                                    title: tag.name,
                                    isSelected: selectedTags.contains(tag.name),
                                    count: tag.count
                                ) {
                                    toggleTag(tag.name)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("タグ一覧") {
                if tagSummaries.isEmpty {
                    Text("タグはまだありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tagSummaries, id: \.id) { (tag: SearchIndexService.TagSummary) in
                        Button {
                            toggleTag(tag.name)
                        } label: {
                            HStack {
                                Text("#\(tag.name)")
                                Spacer()
                                Text("\(tag.count)")
                                    .foregroundStyle(.secondary)
                                if selectedTags.contains(tag.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("タグフィルタ") {
                Picker("一致条件", selection: $matchMode) {
                    Text("AND").tag(TagMatchMode.all)
                    Text("OR").tag(TagMatchMode.any)
                }
                .pickerStyle(.segmented)

                if selectedTags.isEmpty {
                    Text("タグを選択してください")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("選択中: \(selectedTags.sorted().map { "#\($0)" }.joined(separator: " "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("クリア") {
                            selectedTags.removeAll()
                        }
                        .font(.caption)
                    }

                    if filteredEntries.isEmpty {
                        Text("該当するエントリーはありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredEntries) { entry in
                            TimelineRowView(entry: entry, showTags: showTags)
                        }
                    }
                }
            }
        }
        .navigationTitle("タグ")
        .onAppear {
            if !searchIndex.isReady {
                searchIndex.rebuildIndex(modelContext: modelContext)
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

private enum TagMatchMode: String, CaseIterable {
    case all
    case any
}

private struct TagChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    @Environment(\.accessibilityContrast) private var accessibilityContrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("#\(title)")
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(accessibilityContrast == .high ? 0.3 : 0.2) : Color.secondary.opacity(accessibilityContrast == .high ? 0.25 : 0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor, lineWidth: isSelected && accessibilityContrast == .high ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("#\(title)")
        .accessibilityValue("\(count)件、\(isSelected ? "選択中" : "未選択")")
        .accessibilityHint("タグをフィルタに追加します")
    }
}
