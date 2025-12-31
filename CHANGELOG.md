# Changelog

All notable changes to CaleNote will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed - 2026/01/01

#### ScheduleEntry indexing for query performance
- **SwiftData indexes** (`CaleNote/Domain/ScheduleEntry.swift`)
  - Timeline/Sync/Trash queries向けに `source` / `managedByCaleNote` / `googleEventId` / `calendarId` / `startAt` / `endAt` / `syncStatus` / `isDeleted` / `deletedAt` を indexed 化

### Added - 2025/12/31

#### Issue #22 (CAL-22): BackgroundTasks-based sync
- **BackgroundTaskManager** (`Infrastructure/Sync/BackgroundTaskManager.swift`)
  - BGAppRefreshTask での定期同期スケジューリング
  - BGProcessingTask でのインデックス再構築スケジューリング
  - ネットワーク状況と低電力モードに応じた同期間隔調整
- **AppDelegate** (`App/AppDelegate.swift`)
  - BackgroundTasks の登録とバックグラウンド遷移時の再スケジュール
- **Info.plist** (`CaleNote/Info.plist`)
  - BGTaskSchedulerPermittedIdentifiers と UIBackgroundModes を追加

### Changed - 2025/12/31
- **Foreground Sync** (`Features/Timeline/TimelineView.swift`, `Features/Navigation/MainNavigationView.swift`)
  - フォアグラウンド復帰時の即時同期とタイマー管理の最適化

### Added - 2025/12/30

#### Issue #18: Calendar Selection and Multi-Calendar Support (CAL-18)
- **CalendarInfo SwiftData Model** (`Domain/CalendarInfo.swift`)
  - Google Calendar のカレンダー情報をローカルにキャッシュ
  - カレンダーID、名前、色、アクセス権限を保存
  - 表示/非表示設定、同期設定のユーザー設定を管理
  - プライマリカレンダー識別

- **CalendarListService** (`Infrastructure/Settings/CalendarListService.swift`)
  - Google Calendar API からカレンダーリストを取得・キャッシュ
  - 差分同期対応（syncToken使用）
  - カレンダー表示/非表示の切り替え
  - 同期設定の管理
  - カレンダーカラー情報の提供

- **SidebarView** (`Features/Sidebar/SidebarView.swift`)
  - サイドバーUI実装
  - カレンダーリスト表示（カラー、名前、プライマリバッジ）
  - チェックボックスによる表示/非表示切り替え
  - 設定・フィードバックへのアクセス

- **ScheduleEntry.calendarId プロパティ追加**
  - 各エントリーがどのカレンダーに属するかを追跡
  - Google Calendar 同期時に自動設定

- **TimelineView カレンダーフィルタリング**
  - 表示中のカレンダーのみをタイムラインに表示
  - CalendarListService との連携

- **TimelineRowView カレンダーカラー表示**
  - 各エントリーの左側にカレンダーカラーインジケーターを表示
  - Color拡張で16進数カラーコードからSwiftUI Colorへの変換をサポート

- **ContentView サイドバー統合**
  - ハンバーガーメニューでサイドバーを開閉
  - オーバーレイ表示によるモバイルフレンドリーな実装

- **CalendarSettings 拡張**
  - カレンダーリストの同期トークン管理
  - 最終同期日時の記録

- **CalendarSyncService 更新**
  - 新規・既存エントリーにcalendarIdを設定
  - 全日イベントの正確な判定

#### Issue #10 (CAL-10): Sidebar and Navigation Structure
- `/CaleNote/Features/Navigation/` に新規ナビゲーション構造を実装
- **SidebarView.swift**: サイドバービュー
  - カレンダー表示切替（Google Calendar / CaleNote エントリー）
  - 設定画面へのナビゲーション
  - フィードバック・ヘルプ導線
  - Googleアカウント情報表示
- **TopBarView.swift**: トップバービュー
  - サイドバートグルボタン
  - 月表示と月選択ポップオーバー
  - 検索ボタン
  - 今日フォーカスボタン
- **MainNavigationView.swift**: メインナビゲーションビュー
  - サイドバーとタイムラインを統合
  - カレンダー表示フィルタリング機能
  - FAB（新規エントリー作成）ボタン
- ContentView を MainNavigationView を使用するように更新

### Added (from feature/cal-11)
- Restored and integrated JournalEditorView, SettingsView, CalendarSyncState.

### Fixed - 2025/12/30

#### Technical Debt Resolution
- **GoogleAuthService 環境注入**: CaleNoteApp.swift で GoogleAuthService を @StateObject として作成し、environmentObject で子ビューに注入
- **全日イベント対応**: ScheduleEntry に isAllDay プロパティを追加し、Google Calendar の全日イベントをサポート
- **TimelineRowView 改善**: 全日イベントの場合は時刻の代わりに「終日」と表示
- **カレンダー設定管理**: CalendarSettings サービスを作成し、ターゲットカレンダーID を管理
- **ハードコード削除**: CalendarSyncService のハードコードされた "primary" カレンダーID を設定ベースに変更
- **.gitignore 追加**: .claude/ ディレクトリをバージョン管理から除外

これらの修正により、アーキテクチャが改善され、将来的な拡張性が向上しました。

### Added - 2025/12/30

#### Issue #7: Timeline View
- TimelineView.swift でメイン画面のタイムラインビューを実装
  - **日付セクション**: 日付ごとにエントリーをグループ化して表示
  - **時系列表示**: 各日のエントリーを時刻順に並べて表示
  - **混在表示**: Google Calendar イベントと CaleNote ジャーナルを統合表示
  - **検索機能**: タイトル、本文、タグによる検索
  - **今日へフォーカス**: 初回表示時に今日のセクションへ自動スクロール
  - **同期ボタン**: ツールバーから手動同期を実行可能
  - **FAB ボタン**: 右下の＋ボタンで新規エントリー作成（画面は未実装）
- TimelineRowView.swift でエントリー行のUIを実装
  - 時刻表示（開始〜終了）
  - タイトル、本文プレビュー、タグ表示
  - ソースアイコン（カレンダー/ノート）
  - 同期状態バッジ（pending/failed）
- DateSectionHeader.swift で日付セクションヘッダーを実装
  - 今日、昨日、明日の相対日付表示
  - 今日のセクションをハイライト表示（アクセントカラー、ドット、背景）
- ContentView を TimelineView に置き換え

#### Issue #4: Bidirectional Synchronization Service
- CalendarSyncService.swift で Google Calendar との双方向同期を実装
  - **ローカル→Google 同期**: ローカル変更を非同期で Google Calendar に反映
  - **Google→ローカル 同期**: Google Calendar の変更をローカルに反映
  - **差分同期**: syncToken を使用した効率的な差分同期
  - **同期状態管理**: 各エントリーの同期状態を追跡（synced/pending/failed）
  - **競合解決**: Google Calendar を正として競合を解決
  - **バックグラウンド同期**: Timer ベースの定期同期（5分間隔）
  - **リトライ機能**: 失敗した同期の再試行
  - **syncToken 永続化**: UserDefaults による syncToken の保存・復元
  - **時間範囲同期**: 過去90日〜未来365日の範囲で同期
  - **ページネーション対応**: 大量イベントの効率的な取得

#### Issue #3: Google Calendar API Client
- CalendarModels.swift で Google Calendar API v3 のデータ構造を実装
  - CalendarEvent: イベントデータ
  - EventListResponse: イベントリストレスポンス
  - CalendarList: カレンダーリスト
  - GoogleAPIErrorResponse: エラーレスポンス
- GoogleCalendarClient.swift で完全な CRUD 操作を実装
  - イベントの作成、取得、更新、削除
  - カレンダーリスト取得（ページネーション対応）
  - イベントリスト取得（時間範囲フィルタ、ページネーション、syncToken 対応）
  - レート制限（リクエスト間隔 100ms）
  - RetryExecutor による自動リトライ
  - HTTP ステータスコード処理（401, 403, 404, 410, 429, 5xx など）
  - syncToken ベースの差分同期サポート

#### Issue #2: Google Sign-In Authentication
- GoogleAuthService.swift で OAuth 2.0 認証フローを実装
  - サインイン / サインアウト
  - アクセストークンの自動更新
  - 追加スコープのリクエスト
  - Keychain ベースのセッション永続化
- GOOGLE_AUTH_SETUP.md でセットアップガイドを追加
  - Google Cloud Console の設定手順
  - OAuth クライアントの構成方法
  - URL スキームのセットアップ

#### Issue #16: Error Handling and Retry Logic
- CaleNoteError.swift で包括的なエラー型システムを実装
  - NetworkError: ネットワーク関連エラー
  - APIError: Google Calendar API エラー
  - LocalDataError: ローカルデータ永続化エラー
- RetryPolicy.swift で指数バックオフによるリトライロジックを実装
  - デフォルト、アグレッシブ、コンサバティブの3つのプリセットポリシー
  - RetryExecutor actor による並行安全なリトライ実行
- ErrorHandler.swift で一元的なエラー管理サービスを実装

#### Issue #1: SwiftData ScheduleEntry Model
- ScheduleEntry.swift でスケジュールエントリのコアデータモデルを実装
- Google Calendar との同期状態を追跡するための syncStatus プロパティを追加
- タグベースの検索をサポート
- CaleNoteApp.swift に ModelContainer を登録

### Technical Details

- **Swift Concurrency**: すべての API 呼び出しと DB 操作で async/await を使用
- **Actor Isolation**: RetryExecutor を actor として実装し、並行安全性を確保
- **Error Handling**: すべてのサービスで CaleNoteError を使用した一貫したエラー処理
- **Logging**: OSLog による構造化ログ
- **Rate Limiting**: Google Calendar API のレート制限に対応
- **Dependency Injection**: すべてのサービスで依存関係注入パターンを使用

### Dependencies

- GoogleSignIn SDK 9.0+ (Issue #2)
- SwiftData (Issue #1)
- Combine (Issue #16, #2, #4)

## [0.1.0] - 2025/12/30 (Initial Reset)

### Changed
- プロジェクトを最小構成にリセット
- App Layer: CaleNoteApp.swift
- Features Layer: ContentView.swift
- Domain Layer: 空
- Infrastructure Layer: 空
