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
            Section {
                if recentTags.isEmpty {
                    Text(L10n.tr("tags.recent.empty"))
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
            } header: {
                Text(L10n.tr("tags.recent"))
            }

            Section {
                if tagSummaries.isEmpty {
                    Text(L10n.tr("tags.list.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tagSummaries, id: \.id) { (tag: SearchIndexService.TagSummary) in
                        Button {
                            toggleTag(tag.name)
                        } label: {
                            HStack {
                                Text("#\(tag.name)")
                                Spacer()
                                Text(L10n.number(tag.count))
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
            } header: {
                Text(L10n.tr("tags.list"))
            }

            Section {
                Picker(L10n.tr("tags.filter.match_mode"), selection: $matchMode) {
                    Text(L10n.tr("tags.match.and")).tag(TagMatchMode.all)
                    Text(L10n.tr("tags.match.or")).tag(TagMatchMode.any)
                }
                .pickerStyle(.segmented)

                if selectedTags.isEmpty {
                    Text(L10n.tr("tags.filter.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(L10n.tr("tags.filter.selected", selectedTags.sorted().map { "#\($0)" }.joined(separator: " ")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L10n.tr("common.clear")) {
                            selectedTags.removeAll()
                        }
                        .font(.caption)
                    }

                    if filteredEntries.isEmpty {
                        Text(L10n.tr("tags.filter.no_entries"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredEntries) { entry in
                            TimelineRowView(entry: entry, showTags: showTags)
                        }
                    }
                }
            } header: {
                Text(L10n.tr("tags.filter"))
            }
        }
        .navigationTitle(L10n.tr("tags.title"))
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
        let statusText = isSelected ? L10n.tr("common.selected") : L10n.tr("common.not_selected")
        let countText = L10n.number(count)
        let accessibilityKey = count == 1 ? "tags.chip.accessibility.singular" : "tags.chip.accessibility.plural"

        Button(action: action) {
            HStack(spacing: 6) {
                Text("#\(title)")
                Text(L10n.number(count))
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
        .accessibilityValue(L10n.tr(accessibilityKey, countText, statusText))
        .accessibilityHint(L10n.tr("tags.chip.hint"))
    }
}
