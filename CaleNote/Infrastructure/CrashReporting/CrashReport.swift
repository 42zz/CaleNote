//
//  CrashReport.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import Foundation

/// クラッシュレポートデータモデル
struct CrashReport: Codable, Identifiable {
    /// ユニークID
    let id: UUID

    /// 発生日時
    let date: Date

    /// 例外名
    let exceptionName: String

    /// 例外理由
    let exceptionReason: String?

    /// スタックトレース
    let stackTrace: [String]

    /// アプリバージョン
    let appVersion: String

    /// ビルド番号
    let buildNumber: String

    /// デバイスモデル
    let deviceModel: String

    /// OS バージョン
    let osVersion: String

    /// 附加情報
    let additionalInfo: [String: String]?

    /// レポートがファイルに保存されているか
    var isSaved: Bool = false

    /// 読みやすい形式の日時
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    /// レポートの要約
    var summary: String {
        if let reason = exceptionReason {
            return "\(exceptionName): \(reason)"
        }
        return exceptionName
    }

    /// Markdown 形式でのレポート
    var markdownDescription: String {
        var md = """
        # Crash Report

        **日時**: \(formattedDate)
        **例外**: \(exceptionName)
        **バージョン**: \(appVersion) (\(buildNumber))
        **デバイス**: \(deviceModel)
        **OS**: iOS \(osVersion)

        """

        if let reason = exceptionReason {
            md += "\n**理由**: \(reason)\n"
        }

        if !stackTrace.isEmpty {
            md += "\n## スタックトレース\n\n"
            for (index, line) in stackTrace.enumerated() {
                md += "\(index + 1). \(line)\n"
            }
        }

        if let additionalInfo = additionalInfo, !additionalInfo.isEmpty {
            md += "\n## 附加情報\n\n"
            for (key, value) in additionalInfo {
                md += "- **\(key)**: \(value)\n"
            }
        }

        return md
    }
}
