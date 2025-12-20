//
//  TimelineView.swift
//  CaleNote
//
//  Created by Masaya Kawai on 2025/12/20.
//

import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext

    // eventDate で新しい順
    @Query(sort: \JournalEntry.eventDate, order: .reverse)
    private var entries: [JournalEntry]

    @State private var isPresentingEditor = false

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("まだ何もありません", systemImage: "square.and.pencil")
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            JournalDetailView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）")
                                    .font(.headline)

                                Text(entry.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(entry.eventDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("ジャーナル")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor) {
                JournalEditorView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }
}
