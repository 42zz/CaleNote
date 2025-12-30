//
//  SearchIndexService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import Foundation
import SwiftData

/// 検索インデックスを管理するサービス
@MainActor
final class SearchIndexService: ObservableObject {
    // MARK: - Types

    private struct EntryTokens {
        let titlePrefixes: Set<String>
        let tags: Set<String>
        let bodyTokens: Set<String>
    }

    struct TagSummary: Identifiable {
        let id: String
        let name: String
        let count: Int
        let lastUsedAt: Date
    }

    // MARK: - Published

    @Published private(set) var isReady = false
    @Published private(set) var history: [String] = []

    // MARK: - Index Storage

    private var titleIndex: [String: Set<ObjectIdentifier>] = [:]
    private var tagIndex: [String: Set<ObjectIdentifier>] = [:]
    private var bodyIndex: [String: Set<ObjectIdentifier>] = [:]
    private var entryCache: [ObjectIdentifier: ScheduleEntry] = [:]
    private var entryTokens: [ObjectIdentifier: EntryTokens] = [:]

    private let historyKey = "searchHistory"

    // MARK: - Initialization

    init() {
        loadHistory()
    }

    // MARK: - Public API

    func rebuildIndex(modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<ScheduleEntry>()
            let entries = try modelContext.fetch(descriptor)
            rebuildIndex(entries: entries)
        } catch {
            isReady = false
        }
    }

    func rebuildIndex(entries: [ScheduleEntry]) {
        titleIndex.removeAll()
        tagIndex.removeAll()
        bodyIndex.removeAll()
        entryCache.removeAll()
        entryTokens.removeAll()

        for entry in entries {
            indexEntry(entry)
        }
        isReady = true
    }

    func indexEntry(_ entry: ScheduleEntry) {
        let id = ObjectIdentifier(entry)
        entryCache[id] = entry

        let tokens = buildTokens(for: entry)
        entryTokens[id] = tokens

        for prefix in tokens.titlePrefixes {
            titleIndex[prefix, default: []].insert(id)
        }
        for tag in tokens.tags {
            tagIndex[tag, default: []].insert(id)
        }
        for token in tokens.bodyTokens {
            bodyIndex[token, default: []].insert(id)
        }
    }

    func updateEntry(_ entry: ScheduleEntry) {
        let id = ObjectIdentifier(entry)
        if let oldTokens = entryTokens[id] {
            removeFromIndex(id: id, tokens: oldTokens)
        }
        indexEntry(entry)
    }

    func removeEntry(_ entry: ScheduleEntry) {
        let id = ObjectIdentifier(entry)
        if let oldTokens = entryTokens[id] {
            removeFromIndex(id: id, tokens: oldTokens)
        }
        entryCache.removeValue(forKey: id)
        entryTokens.removeValue(forKey: id)
    }

    func search(query: String, includeBody: Bool) -> [ScheduleEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = normalizedText(trimmed)
        let tagTokens = TagParser.extract(from: trimmed).map { normalizedText($0) }
        let nonTagQuery = normalizedText(
            trimmed.replacingOccurrences(of: "#", with: " ")
        )
        let queryTokens = nonTagQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        var resultIDs: Set<ObjectIdentifier>?

        let tagSet = Set(tagTokens)
        let nonTagTokens = queryTokens.filter { !tagSet.contains($0) }

        if let titleToken = nonTagTokens.first, !titleToken.isEmpty {
            if let titleMatches = titleIndex[titleToken] {
                resultIDs = titleMatches
            } else {
                resultIDs = []
            }
        }

        if !tagTokens.isEmpty {
            for tag in tagTokens {
                let matches = tagIndex[tag] ?? []
                if resultIDs == nil {
                    resultIDs = matches
                } else {
                    resultIDs = resultIDs!.intersection(matches)
                }
            }
        }

        var results = entries(from: resultIDs)

        if includeBody, !nonTagTokens.isEmpty {
            var bodyIDs: Set<ObjectIdentifier>?
            for token in nonTagTokens {
                let matches = bodyIndex[token] ?? []
                if bodyIDs == nil {
                    bodyIDs = matches
                } else {
                    bodyIDs = bodyIDs!.intersection(matches)
                }
            }
            let bodyResults = entries(from: bodyIDs)
            results.append(contentsOf: bodyResults)
        }

        let unique = Dictionary(grouping: results, by: { ObjectIdentifier($0) })
        return unique.values.compactMap { $0.first }
            .sorted { $0.startAt > $1.startAt }
    }

    func addHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        history.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        history.insert(trimmed, at: 0)
        if history.count > 20 {
            history = Array(history.prefix(20))
        }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func tagSummaries(limit: Int? = nil) -> [TagSummary] {
        var stats: [String: (name: String, count: Int, lastUsedAt: Date)] = [:]
        for entry in entryCache.values {
            let lastUsed = entry.updatedAt
            for tag in entry.tags {
                let normalized = normalizedText(tag)
                guard !normalized.isEmpty else { continue }
                if var existing = stats[normalized] {
                    existing.count += 1
                    if lastUsed > existing.lastUsedAt {
                        existing.lastUsedAt = lastUsed
                    }
                    stats[normalized] = existing
                } else {
                    stats[normalized] = (name: tag, count: 1, lastUsedAt: lastUsed)
                }
            }
        }

        var summaries = stats.map {
            TagSummary(id: $0.key, name: $0.value.name, count: $0.value.count, lastUsedAt: $0.value.lastUsedAt)
        }
        summaries.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if let limit {
            return Array(summaries.prefix(limit))
        }
        return summaries
    }

    func recentTags(limit: Int = 10) -> [TagSummary] {
        let summaries = tagSummaries()
        return summaries
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(limit)
            .map { $0 }
    }

    func tagSuggestions(limit: Int = 10) -> [String] {
        tagSummaries(limit: limit).map { $0.name }
    }

    func entries(matching tags: [String], matchAll: Bool) -> [ScheduleEntry] {
        let normalizedTags = tags
            .map { normalizedText($0) }
            .filter { !$0.isEmpty }
        guard !normalizedTags.isEmpty else { return [] }

        var resultIDs: Set<ObjectIdentifier>?
        for tag in normalizedTags {
            let matches = tagIndex[tag] ?? []
            if resultIDs == nil {
                resultIDs = matches
            } else {
                resultIDs = matchAll
                    ? resultIDs!.intersection(matches)
                    : resultIDs!.union(matches)
            }
        }

        return entries(from: resultIDs)
            .sorted { $0.startAt > $1.startAt }
    }

    // MARK: - Helpers

    private func buildTokens(for entry: ScheduleEntry) -> EntryTokens {
        let title = normalizedText(entry.title)
        let titleTokens = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var prefixes: Set<String> = []
        for token in titleTokens {
            prefixes.formUnion(prefixesForToken(token))
        }

        let tags = Set(entry.tags.map { normalizedText($0) })
        let bodyTokens = Set(tokenizeBody(entry.body))

        return EntryTokens(titlePrefixes: prefixes, tags: tags, bodyTokens: bodyTokens)
    }

    private func prefixesForToken(_ token: String) -> Set<String> {
        var result: Set<String> = []
        let maxLength = min(token.count, 50)
        if maxLength == 0 { return result }
        for i in 1...maxLength {
            let prefix = String(token.prefix(i))
            result.insert(prefix)
        }
        return result
    }

    private func tokenizeBody(_ body: String?) -> [String] {
        guard let body, !body.isEmpty else { return [] }
        let normalized = normalizedText(body)
        let separators = CharacterSet.alphanumerics.inverted
        return normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func entries(from ids: Set<ObjectIdentifier>?) -> [ScheduleEntry] {
        guard let ids = ids else { return [] }
        return ids.compactMap { entryCache[$0] }
    }

    private func removeFromIndex(id: ObjectIdentifier, tokens: EntryTokens) {
        for prefix in tokens.titlePrefixes {
            titleIndex[prefix]?.remove(id)
            if titleIndex[prefix]?.isEmpty == true {
                titleIndex.removeValue(forKey: prefix)
            }
        }
        for tag in tokens.tags {
            tagIndex[tag]?.remove(id)
            if tagIndex[tag]?.isEmpty == true {
                tagIndex.removeValue(forKey: tag)
            }
        }
        for token in tokens.bodyTokens {
            bodyIndex[token]?.remove(id)
            if bodyIndex[token]?.isEmpty == true {
                bodyIndex.removeValue(forKey: token)
            }
        }
    }

    private func normalizedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func loadHistory() {
        if let stored = UserDefaults.standard.array(forKey: historyKey) as? [String] {
            history = stored
        }
    }

    private func saveHistory() {
        UserDefaults.standard.set(history, forKey: historyKey)
    }
}
