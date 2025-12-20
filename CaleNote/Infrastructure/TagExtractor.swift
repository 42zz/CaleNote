import Foundation

enum TagExtractor {
    // 例: "今日は #振り返り と #SwiftUI" -> ["振り返り", "SwiftUI"]
    static func extract(from text: String) -> [String] {
        // # のあとに「空白・改行・#」以外が続く部分を拾う
        // 記号まで厳密にやると沼るので、まずは現実路線
        let pattern = #"#([^\s#]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        let tags = matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }

        // 重複排除（同じ本文内に複数回出ても1回扱い）
        // 表示用途なので順序は維持
        var seen = Set<String>()
        var unique: [String] = []
        for t in tags {
            if !seen.contains(t) {
                seen.insert(t)
                unique.append(t)
            }
        }
        return unique
    }
}
