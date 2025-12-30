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
            .navigationTitle("検索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "タイトル、タグ、本文"
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
    }

    private var historyView: some View {
        List {
            if searchIndex.history.isEmpty {
                Text("検索履歴はありません")
                    .foregroundStyle(.secondary)
            } else {
                Section("検索履歴") {
                    ForEach(searchIndex.history, id: \.self) { item in
                        Button {
                            searchText = item
                        } label: {
                            Text(item)
                        }
                    }
                    Button("履歴をクリア", role: .destructive) {
                        searchIndex.clearHistory()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var resultsView: some View {
        List {
            if results.isEmpty {
                Text(isSearchingBody ? "検索中..." : "結果がありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedResults, id: \.date) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            TimelineRowView(entry: entry, showTags: showTags)
                        }
                    } header: {
                        DateSectionHeader(date: section.date, isToday: false)
                    }
                }
            }
        }
        .listStyle(.plain)
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
