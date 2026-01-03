//
//  CaleNoteSchema.swift
//  CaleNote
//
//  Created by Claude Code on 2025/01/03.
//

import Foundation
import SwiftData

/// CaleNote アプリケーションスキーマ バージョン1
///
/// 初期リリース版スキーマ
/// - ScheduleEntry: スケジュールエントリー（Google Calendar イベントとの1対1対応）
/// - CalendarInfo: カレンダー情報
enum CaleNoteSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScheduleEntry.self, CalendarInfo.self]
    }
}

/// スキーマの現在のバージョン
typealias CurrentSchema = CaleNoteSchemaV1

// MARK: - Future Schema Versions

/*
 将来的にスキーマを変更する場合は、新しいバージョンを追加：

 enum CaleNoteSchemaV2: VersionedSchema {
     static var versionIdentifier = Schema.Version(2, 0, 0)
     static var models: [any PersistentModel.Type] {
         [ScheduleEntry.self, CalendarInfo.self, NewModel.self]
     }
 }

 そして、MigrationStage を追加して V1 から V2 への移行を定義
 */
