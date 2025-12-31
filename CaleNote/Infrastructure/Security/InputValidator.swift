//
//  InputValidator.swift
//  CaleNote
//
//  Created by Codex on 2025/12/30.
//

import Foundation

enum InputValidator {
    static let maxTitleLength = 200
    static let maxBodyLength = 10_000

    static func sanitizeTitle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return removeControlCharacters(from: trimmed)
    }

    static func sanitizeBody(_ text: String) -> String {
        removeControlCharacters(from: text)
    }

    static func validate(title: String, body: String) -> String? {
        if title.count > maxTitleLength {
            return L10n.tr("validation.title.max_length", L10n.number(maxTitleLength))
        }
        if body.count > maxBodyLength {
            return L10n.tr("validation.body.max_length", L10n.number(maxBodyLength))
        }
        return nil
    }

    private static func removeControlCharacters(from text: String) -> String {
        let filteredScalars = text.unicodeScalars.filter { !$0.properties.isControl }
        return String(String.UnicodeScalarView(filteredScalars))
    }
}
