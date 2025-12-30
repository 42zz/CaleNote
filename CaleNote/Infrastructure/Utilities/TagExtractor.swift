//
//  TagExtractor.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Foundation

enum TagExtractor {
    static func extract(from text: String?) -> [String] {
        guard let text = text else { return [] }
        let pattern = "#[^\\s#]+"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            
            return matches.map { match in
                if let range = Range(match.range, in: text) {
                    return String(text[range]).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "#", with: "")
                }
                return ""
            }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
}

