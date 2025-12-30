//
//  TagParser.swift
//  CaleNote
//
//  Created by Codex on 2025/12/30.
//

import Foundation

enum TagParser {
    private static let maxTagLength = 50
    /// Extract tags from a single text.
    static func extract(from text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return extract(from: [text])
    }

    /// Extract tags from multiple text fields (e.g., title + body), de-duplicated.
    static func extract(from texts: [String?]) -> [String] {
        let combined = texts
            .compactMap { $0 }
            .joined(separator: "\n")
        guard !combined.isEmpty else { return [] }

        let pattern = "#[^\\s#]+"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(combined.startIndex..<combined.endIndex, in: combined)
            let matches = regex.matches(in: combined, options: [], range: range)

            var seen: Set<String> = []
            var results: [String] = []
            for match in matches {
                guard let range = Range(match.range, in: combined) else { continue }
                let raw = String(combined[range])
                let tag = sanitize(
                    raw.replacingOccurrences(of: "#", with: "")
                )
                let normalized = normalize(tag)
                guard !tag.isEmpty, !normalized.isEmpty else { continue }
                guard tag.count <= maxTagLength else { continue }
                if seen.insert(normalized).inserted {
                    results.append(tag)
                }
            }
            return results
        } catch {
            return []
        }
    }

    /// Normalize a tag for de-duplication and indexing.
    static func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sanitize(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredScalars = trimmed.unicodeScalars.filter { !$0.properties.isControl }
        return String(String.UnicodeScalarView(filteredScalars))
    }
}
