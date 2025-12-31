//
//  SearchView.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var searchIndex: SearchIndexService

    @AppStorage("timelineShowTags") private var showTags = true

    @State private var searchText = ""
    @State private var results: [ScheduleEntry] = []
    @State private var isSearchingBody = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    historyView
                } else {
                    resultsView
                }
            }
            .navigationTitle(L10n.tr("search.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSearchingBody {
                        ProgressView()
                            .accessibilityLabel(L10n.tr("search.in_progress"))
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.tr("search.prompt")
            )
            .onSubmit(of: .search) {
                searchIndex.addHistory(searchText)
            }
            .onAppear {
                if !searchIndex.isReady {
                    searchIndex.rebuildIndex(modelContext: modelContext)
                }
            }
            .onChange(of: searchText) { _, newValue in
                handleSearchChange(newValue)
            }
        }
        .accessibilityIdentifier("searchView")
    }

    private var historyView: some View {
        List {
            if searchIndex.history.isEmpty {
                Text(L10n.tr("search.history.empty"))
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(searchIndex.history, id: \.self) { item in
                        Button {
                            searchText = item
                        } label: {
                            Text(item)
                        }
                    }
                    Button(L10n.tr("search.history.clear"), role: .destructive) {
                        searchIndex.clearHistory()
                    }
                } header: {
                    Text(L10n.tr("search.history.title"))
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("searchHistoryList")
    }

    private var resultsView: some View {
        Group {
            if results.isEmpty {
                if isSearchingBody {
                    SearchLoadingStateView(query: searchText)
                } else {
                    SearchEmptyStateView(query: searchText)
                }
            } else {
                List {
                    if isSearchingBody {
                        Section {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(L10n.tr("search.body.in_progress"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(L10n.tr("search.in_progress"))
                        }
                    }

                    ForEach(groupedResults, id: \.date) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    TimelineRowView(entry: entry, showTags: showTags)
                                }
                            }
                        } header: {
                            DateSectionHeader(date: section.date, isToday: false)
                        }
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier("searchResultsList")
            }
        }
    }

    private var groupedResults: [(date: Date, entries: [ScheduleEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: results) { entry in
            calendar.startOfDay(for: entry.startAt)
        }
        return grouped
            .map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func handleSearchChange(_ value: String) {
        searchTask?.cancel()
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            results = []
            isSearchingBody = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            let quick = searchIndex.search(query: query, includeBody: false)
            let shouldSearchBody = query.count >= 3
            await MainActor.run {
                results = quick
                isSearchingBody = shouldSearchBody
            }

            if shouldSearchBody {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let full = searchIndex.search(query: query, includeBody: true)
                await MainActor.run {
                    results = full
                    isSearchingBody = false
                }
            } else {
                await MainActor.run {
                    isSearchingBody = false
                }
            }
        }
    }
}

private struct SearchEmptyStateView: View {
    let query: String

    var body: some View {
        EmptyStateView(
            title: L10n.tr("search.empty.title"),
            message: L10n.tr("search.empty.message", query),
            systemImage: "magnifyingglass",
            detail: L10n.tr("search.empty.detail"),
            footnote: L10n.tr("search.empty.footnote")
        )
    }
}

private struct SearchLoadingStateView: View {
    let query: String

    var body: some View {
        LoadingStateView(
            title: L10n.tr("search.in_progress"),
            message: L10n.tr("search.loading.message", query),
            detail: L10n.tr("search.loading.detail")
        )
    }
}
