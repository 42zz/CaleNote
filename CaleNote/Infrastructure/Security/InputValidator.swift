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
            return "タイトルは\(maxTitleLength)文字以内で入力してください"
        }
        if body.count > maxBodyLength {
            return "本文は\(maxBodyLength)文字以内で入力してください"
        }
        return nil
    }

    private static func removeControlCharacters(from text: String) -> String {
        let controlCharacters = CharacterSet.controlCharacters
        return text.unicodeScalars
            .filter { !controlCharacters.contains($0) }
            .map { String($0) }
            .joined()
    }
}
